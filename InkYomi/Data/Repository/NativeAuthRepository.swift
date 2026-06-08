import Foundation
import SwiftData
import UIKit

/// Actor-based auth repository with serialized token refresh.
/// Uses Swift actor instead of Mutex (Android pattern).
actor NativeAuthRepository: AuthRepository {
    private let authAPI: AuthAPIService
    private let keychain: KeychainManager
    private let appState: AppState

    // Wiped on sign-out alongside the auth keychain. These are plain value
    // types / SwiftData containers that depend on nothing back here, so there
    // is no retain or initialization cycle (all constructed before this repo
    // in DependencyContainer).
    private let transportKeychain: KeychainManager
    private let passphraseKeychain: KeychainManager
    private let modelContainer: ModelContainer

    private var cachedAccessToken: String?
    private var cachedExpiry: Date?
    private var refreshTask: Task<String?, Error>?

    init(
        authAPI: AuthAPIService,
        keychain: KeychainManager,
        appState: AppState,
        transportKeychain: KeychainManager,
        passphraseKeychain: KeychainManager,
        modelContainer: ModelContainer
    ) {
        self.authAPI = authAPI
        self.keychain = keychain
        self.appState = appState
        self.transportKeychain = transportKeychain
        self.passphraseKeychain = passphraseKeychain
        self.modelContainer = modelContainer

        // Restore cached access token from the Keychain (sensitive — no longer
        // in UserDefaults). Expiry stays in UserDefaults (non-sensitive).
        self.cachedAccessToken = try? keychain.readString(forKey: Constants.Keychain.AuthKey.accessToken)
        if let expiryInterval = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.accessTokenExpiry) as? TimeInterval {
            self.cachedExpiry = Date(timeIntervalSince1970: expiryInterval)
        }
    }

    func login(email: String, password: String) async throws {
        let deviceName = await deviceModelName()
        let response = try await authAPI.login(
            email: email,
            password: password,
            deviceId: appState.deviceId,
            deviceName: deviceName
        )
        storeTokens(response)
        await MainActor.run {
            appState.authState = .authenticated(response.user.toDomain())
            // Surface the at-capacity signal exactly once per sign-in. A
            // clean login resets it so a prior warning doesn't linger.
            appState.deviceLimitReached = response.deviceLimitReached ?? false
        }
    }

    func refresh() async throws {
        guard let refreshToken = try keychain.readString(forKey: Constants.Keychain.AuthKey.refreshToken) else {
            // No token — terminal. Caller decides whether to sign out;
            // for the standalone `refresh()` API we don't auto-signOut.
            throw AuthFailure.noRefreshToken
        }

        do {
            let response = try await authAPI.refresh(
                refreshToken: refreshToken,
                deviceId: appState.deviceId
            )
            storeTokens(response)
            await MainActor.run {
                appState.authState = .authenticated(response.user.toDomain())
            }
        } catch {
            throw AuthFailure.classify(error)
        }
    }

    func forgotPassword(email: String) async throws {
        _ = try await authAPI.forgotPassword(email: email)
    }

    func signOut() async {
        cachedAccessToken = nil
        cachedExpiry = nil
        refreshTask = nil

        // Auth state in UserDefaults (non-sensitive remnants). The access
        // token, email, and refresh token live under the auth keychain and
        // are cleared by `keychain.deleteAll()` below.
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.accessTokenExpiry)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userProfileId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userProfileDisplayName)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.deviceRegistrationId)
        try? keychain.deleteAll()

        // Full local wipe of all user data so a signed-out device retains
        // nothing readable by the next user. Best-effort: each step is
        // isolated so a single failure never blocks the sign-out itself.
        wipeAllLocalUserData()

        await MainActor.run {
            appState.authState = .unauthenticated
            appState.deviceRegistrationId = nil
        }
    }

    /// Erase every piece of local user data beyond the auth keychain:
    /// LCP transport secrets + passphrases, downloaded EPUBs (owned +
    /// borrowed), and the SwiftData store (sessions, bookmarks, highlights,
    /// telemetry, cached book/loan rows). Best-effort throughout.
    private func wipeAllLocalUserData() {
        // 1. LCP key material (separate keychain services from auth).
        try? transportKeychain.deleteAll()
        try? passphraseKeychain.deleteAll()

        // 2. Downloaded EPUBs. Both directories are recreated on demand by
        //    the download paths (BookRepositoryImpl / LendingDownloadManager),
        //    so deleting them outright is safe.
        let fm = FileManager.default
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? fm.removeItem(at: documents.appendingPathComponent("books", isDirectory: true))
            try? fm.removeItem(at: documents.appendingPathComponent("lending", isDirectory: true))
        }

        // 3. SwiftData rows. Batch-delete every model type on a fresh context
        //    (the live container/mainContext stays usable for the rest of the
        //    app). Wrapped so an empty store or a single failing type can't
        //    abort the wipe.
        let context = ModelContext(modelContainer)
        do {
            try context.delete(model: CachedBookModel.self)
            try context.delete(model: LoanCacheModel.self)
            try context.delete(model: BookmarkModel.self)
            try context.delete(model: HighlightModel.self)
            try context.delete(model: ReadingSessionModel.self)
            try context.delete(model: ReadingTelemetryEventModel.self)
            try context.delete(model: InstrumentedLocationModel.self)
            try context.delete(model: PendingSpanReadModel.self)
            try context.delete(model: AccountingManifestModel.self)
            try context.save()
        } catch {
            // Best-effort — never block sign-out on a persistence hiccup.
        }
    }

    func getAccessToken() async -> String? {
        // If token is still fresh, return it
        if let token = cachedAccessToken, let expiry = cachedExpiry {
            if Date().addingTimeInterval(Constants.tokenRefreshMarginSeconds) < expiry {
                return token
            }
        }

        // Serialized refresh: if a refresh is already in flight, wait for it
        if let existingTask = refreshTask {
            return try? await existingTask.value
        }

        let task = Task<String?, Error> { [weak self] in
            guard let self else { return nil }
            // Re-check after acquiring the task slot
            if let token = await self.cachedAccessToken, let expiry = await self.cachedExpiry {
                if Date().addingTimeInterval(Constants.tokenRefreshMarginSeconds) < expiry {
                    return token
                }
            }
            do {
                try await self.refresh()
                return await self.cachedAccessToken
            } catch let failure as AuthFailure where failure.terminal {
                // Server-driven sign-out: explicit `invalid_grant` /
                // `unauthorized_client` / `invalid_token` from the auth
                // server. Wipe local state and bounce to login.
                await self.signOut()
                return nil
            } catch {
                // Transient (network down, 5xx, ambiguous 401, timeout).
                // Keep the user signed in — this individual API call will
                // fail without auth, but the next one retries. This is the
                // Kindle-style "stay logged in" behavior.
                return nil
            }
        }
        refreshTask = task
        let result = try? await task.value
        refreshTask = nil
        return result
    }

    /// Attempt to restore session from stored tokens on app launch.
    ///
    /// Kindle-style sticky semantics: a launch with a stored profile keeps
    /// the user signed in even if the immediate refresh fails for transient
    /// reasons (offline launch, server hiccup). Only an explicit terminal
    /// rejection from the auth server (or no refresh token at all) drops
    /// the user back to the login screen.
    func restoreSession() async {
        if cachedAccessToken != nil, let expiry = cachedExpiry, Date() < expiry {
            if let profile = storedUserProfile() {
                await MainActor.run {
                    appState.authState = .authenticated(profile)
                }
                return
            }
        }

        let storedProfile = storedUserProfile()

        guard (try? keychain.readString(forKey: Constants.Keychain.AuthKey.refreshToken)) != nil else {
            await MainActor.run {
                appState.authState = .unauthenticated
            }
            return
        }

        do {
            try await refresh()
        } catch let failure as AuthFailure where failure.terminal {
            // Server explicitly rejected the stored refresh token — sign
            // out and surface the login screen.
            await signOut()
        } catch {
            // Transient failure. Keep the user signed in with whatever
            // cached profile we have so the app surfaces useful UI rather
            // than bouncing them to login on every offline cold start.
            // The next access-token request will retry; if connectivity
            // returns the session resumes seamlessly.
            if let profile = storedProfile {
                await MainActor.run {
                    appState.authState = .authenticated(profile)
                }
            } else {
                await MainActor.run {
                    appState.authState = .unauthenticated
                }
            }
        }
    }

    // MARK: - Private

    private func storeTokens(_ response: DeviceAuthResponse) {
        cachedAccessToken = response.accessToken
        // expiresAt is epoch milliseconds (Int64), same as Android's Long
        let expiry = Date(timeIntervalSince1970: Double(response.expiresAt) / 1000.0)
        cachedExpiry = expiry

        // Access token is sensitive — Keychain, not UserDefaults. Expiry is
        // not sensitive and stays in UserDefaults.
        try? keychain.save(response.accessToken, forKey: Constants.Keychain.AuthKey.accessToken)
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: Constants.UserDefaultsKeys.accessTokenExpiry)

        try? keychain.save(response.refreshToken, forKey: Constants.Keychain.AuthKey.refreshToken)

        // The server assigns the `user_devices.id` (row PK) on device-login
        // and returns it as `deviceRegistrationId`. Persist it so the
        // device-list screen can recompute `isCurrent` correctly (the
        // backend's own `is_current` keys off this row id, not our
        // client-side `device_id`). Device-refresh omits this field, so
        // only overwrite when it's actually present — never clobber a
        // previously-good value with nil on a token refresh.
        if let registrationId = response.deviceRegistrationId {
            UserDefaults.standard.set(registrationId, forKey: Constants.UserDefaultsKeys.deviceRegistrationId)
            Task { @MainActor in appState.deviceRegistrationId = registrationId }
        }

        let user = response.user
        UserDefaults.standard.set(user.id, forKey: Constants.UserDefaultsKeys.userProfileId)
        // Email is sensitive (PII) — Keychain, not UserDefaults. Id and
        // display name stay in UserDefaults (non-sensitive).
        try? keychain.save(user.email, forKey: Constants.Keychain.AuthKey.userProfileEmail)
        UserDefaults.standard.set(user.displayName, forKey: Constants.UserDefaultsKeys.userProfileDisplayName)
    }

    private func storedUserProfile() -> UserProfile? {
        guard let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userProfileId),
              let email = try? keychain.readString(forKey: Constants.Keychain.AuthKey.userProfileEmail) else {
            return nil
        }
        return UserProfile(
            id: id,
            email: email,
            displayName: UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userProfileDisplayName)
        )
    }

    private func deviceModelName() async -> String {
        await MainActor.run {
            UIDevice.current.model
        }
    }
}
