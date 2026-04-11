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

        // Restore cached access token from UserDefaults
        self.cachedAccessToken = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.accessToken)
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
            await signOut()
            throw APIError.unauthorized
        }

        let response = try await authAPI.refresh(
            refreshToken: refreshToken,
            deviceId: appState.deviceId
        )
        storeTokens(response)
        await MainActor.run {
            appState.authState = .authenticated(response.user.toDomain())
        }
    }

    func forgotPassword(email: String) async throws {
        _ = try await authAPI.forgotPassword(email: email)
    }

    func signOut() async {
        cachedAccessToken = nil
        cachedExpiry = nil
        refreshTask = nil

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
            } catch {
                await self.signOut()
                return nil
            }
        }
        refreshTask = task
        let result = try? await task.value
        refreshTask = nil
        return result
    }

    /// Attempt to restore session from stored tokens on app launch.
    func restoreSession() async {
        if cachedAccessToken != nil, let expiry = cachedExpiry, Date() < expiry {
            if let profile = storedUserProfile() {
                await MainActor.run {
                    appState.authState = .authenticated(profile)
                }
                return
            }
        }

        // Try refreshing
        if (try? keychain.readString(forKey: "refreshToken")) != nil {
            do {
                try await refresh()
                return
            } catch {
                // Fall through to unauthenticated
            }
        }

        await MainActor.run {
            appState.authState = .unauthenticated
        }
    }

    // MARK: - Private

    private func storeTokens(_ response: DeviceAuthResponse) {
        cachedAccessToken = response.accessToken
        // expiresAt is epoch milliseconds (Int64), same as Android's Long
        let expiry = Date(timeIntervalSince1970: Double(response.expiresAt) / 1000.0)
        cachedExpiry = expiry

        UserDefaults.standard.set(response.accessToken, forKey: Constants.UserDefaultsKeys.accessToken)
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
