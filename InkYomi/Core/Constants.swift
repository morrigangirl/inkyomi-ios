import Foundation

enum Constants {
    static let baseURL = URL(string: "https://inkcolors.shop/api/")!
    static let tokenRefreshMarginSeconds: TimeInterval = 60
    static let searchDebounceMilliseconds: UInt64 = 300
    static let tabStalenessThresholdSeconds: TimeInterval = 30
    static let spanBatchSize = 500
    static let spanUploadThrottleSeconds: TimeInterval = 30
    static let spanPeriodicDrainSeconds: TimeInterval = 300
    static let httpTimeoutSeconds: TimeInterval = 30
    static let continueReadingLimit = 5
    static let continueReadingMaxProgress: Float = 0.98
    static let maxLoanRenewals = 2
    static let decryptionCacheSize = 16

    enum Keychain {
        static let authService = "shop.inkcolors.InkYomi.auth"
        static let transportService = "shop.inkcolors.InkYomi.transport"
        static let passphraseService = "shop.inkcolors.InkYomi.passphrase"
        static let deviceKeyService = "shop.inkcolors.InkYomi.deviceKey"
        /// Keychain key (inside the authService) for the bearer access
        /// token. Previously stored in UserDefaults; migrated on first
        /// launch of builds carrying this key.
        static let accessTokenKey = "accessToken"
    }

    enum UserDefaultsKeys {
        static let accessToken = "accessToken"
        static let accessTokenExpiry = "accessTokenExpiry"
        static let deviceId = "deviceId"
        static let userProfileId = "userProfileId"
        static let userProfileEmail = "userProfileEmail"
        static let userProfileDisplayName = "userProfileDisplayName"
    }

    enum BackgroundTask {
        static let spanUpload = "shop.inkcolors.InkYomi.spanUpload"
        static let loanRenewal = "shop.inkcolors.InkYomi.loanRenewal"
    }

    enum DRM {
        static let userWrapInfo = "inkyomi/v1/user-wrap"
        static let transportKeyInfo = "inkyomi/v1/transport"
        static let providerCertFilename = "inkyomi-provider-cert"
    }

    /// Keycloak OAuth 2.0 client configuration for the mobile reader.
    /// Mirrors the `inkcolors-reader-mobile` realm client documented in
    /// pearlescent-dream/docs/KEYCLOAK_MOBILE_SETUP.md. Changes here
    /// must stay in sync with the Keycloak realm config — issuer URL,
    /// client id, and redirect URI are all matched server-side.
    enum Keycloak {
        static let issuerURL = URL(string: "https://auth.inkcolors.shop/realms/InkColors-Shop")!
        static let clientId = "inkcolors-reader-mobile"
        static let redirectURI = URL(string: "shop.inkcolors.inkyomi://auth/callback")!
        static let scopes = ["openid", "profile", "email", "offline_access"]
        /// Key under `Constants.Keychain.authService` where the
        /// OIDAuthState archive is persisted. Distinct from
        /// `accessTokenKey` so the legacy NativeAuthRepository path
        /// keeps working in parallel during the lazy transition.
        static let authStateKey = "oidAuthState"
        /// Hosted password-reset page on Keycloak. Surfaced via the
        /// ForgotPassword screen — there's no native API for this
        /// once we're on OAuth.
        static let resetPasswordURL = URL(string: "https://auth.inkcolors.shop/realms/InkColors-Shop/login-actions/reset-credentials?client_id=inkcolors-reader-mobile")!
    }
}
