import Foundation
import UIKit

/// Actor-based auth repository with serialized token refresh.
/// Uses Swift actor instead of Mutex (Android pattern).
actor NativeAuthRepository: AuthRepository {
    private let authAPI: AuthAPIService
    private let keychain: KeychainManager
    private let appState: AppState

    private var cachedAccessToken: String?
    private var cachedExpiry: Date?
    private var refreshTask: Task<String?, Error>?

    init(authAPI: AuthAPIService, keychain: KeychainManager, appState: AppState) {
        self.authAPI = authAPI
        self.keychain = keychain
        self.appState = appState

        // Restore cached access token from the Keychain. The expiry is a
        // plain timestamp, not a secret, so it stays in UserDefaults
        // (cheap, no Keychain prompt on app launch). Migration: any
        // pre-existing UserDefaults-stored access token is moved into
        // the Keychain on first launch under this build to avoid
        // forcing a re-login.
        if let legacyToken = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.accessToken) {
            try? keychain.save(legacyToken, forKey: Constants.Keychain.accessTokenKey)
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.accessToken)
        }
        self.cachedAccessToken = try? keychain.readString(forKey: Constants.Keychain.accessTokenKey)
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
        }
    }

    func refresh() async throws {
        guard let refreshToken = try keychain.readString(forKey: "refreshToken") else {
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

        // Legacy UserDefaults access token key — keep the removal in
        // case a previous build left one behind.
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.accessToken)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.accessTokenExpiry)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userProfileId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userProfileEmail)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.userProfileDisplayName)
        try? keychain.deleteAll()

        await MainActor.run {
            appState.authState = .unauthenticated
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

        guard (try? keychain.readString(forKey: "refreshToken")) != nil else {
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

        // Access token → Keychain (encrypted at rest, sandboxed per app,
        // not included in iCloud/iTunes backups by default).
        try? keychain.save(response.accessToken, forKey: Constants.Keychain.accessTokenKey)
        // Expiry is a public timestamp — UserDefaults is fine. Keeps
        // restoreSession() cheap by avoiding a Keychain round-trip
        // just to know whether the cached token is still valid.
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: Constants.UserDefaultsKeys.accessTokenExpiry)

        try? keychain.save(response.refreshToken, forKey: "refreshToken")

        let user = response.user
        UserDefaults.standard.set(user.id, forKey: Constants.UserDefaultsKeys.userProfileId)
        UserDefaults.standard.set(user.email, forKey: Constants.UserDefaultsKeys.userProfileEmail)
        UserDefaults.standard.set(user.displayName, forKey: Constants.UserDefaultsKeys.userProfileDisplayName)
    }

    private func storedUserProfile() -> UserProfile? {
        guard let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userProfileId),
              let email = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userProfileEmail) else {
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
