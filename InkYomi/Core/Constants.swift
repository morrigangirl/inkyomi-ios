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

    enum URLScheme {
        static let scheme = "inkcolors"
        static let checkoutSuccess = "inkcolors://checkout/success"
        static let checkoutCancel = "inkcolors://checkout/cancel"
    }

    enum Keychain {
        static let authService = "shop.inkcolors.InkYomi.auth"
        static let transportService = "shop.inkcolors.InkYomi.transport"
        static let passphraseService = "shop.inkcolors.InkYomi.passphrase"
        static let deviceKeyService = "shop.inkcolors.InkYomi.deviceKey"
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
}
