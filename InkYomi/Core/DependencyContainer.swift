import Foundation
import Observation
import SwiftData

@Observable
final class DependencyContainer: @unchecked Sendable {
    static let shared = DependencyContainer()

    let appState: AppState
    let modelContainer: ModelContainer

    // Security
    let authKeychain: KeychainManager
    let transportKeychain: KeychainManager
    let passphraseKeychain: KeychainManager

    // API
    let apiClient: APIClient
    let authAPIService: AuthAPIService

    // Services
    let catalogAPIService: CatalogAPIService
    let discoveryAPIService: DiscoveryAPIService
    let searchAPIService: SearchAPIService
    let savedSearchesAPIService: SavedSearchesAPIService
    let entitlementAPIService: EntitlementAPIService
    let deviceAPIService: DeviceAPIService
    let accountAPIService: AccountAPIService
    let opdsCatalogAPIService: OpdsCatalogAPIService
    let opdsLendingAPIService: OpdsLendingAPIService
    let spanTelemetryAPIService: SpanTelemetryAPIService
    let readerAPIService: ReaderAPIService
    let readerSyncAPIService: ReaderSyncAPIService

    // Repositories
    let authRepository: NativeAuthRepository
    let catalogRepository: CatalogRepositoryImpl
    let discoveryRepository: DiscoveryRepositoryImpl
    let searchRepository: SearchRepositoryImpl
    let savedSearchesRepository: SavedSearchesRepositoryImpl
    let libraryRepository: LibraryRepositoryImpl
    let deviceRepository: DeviceRepositoryImpl
    let accountRepository: AccountRepositoryImpl
    let lendingRepository: LendingRepositoryImpl
    let spanTelemetryRepository: SpanTelemetryRepository
    let bookRepository: BookRepositoryImpl
    let storageRepository: StorageRepository
    let loanRenewalCoordinator: LoanRenewalCoordinator
    let readerSyncCoordinator: ReaderSyncCoordinator

    // Preferences
    let recentSearches: RecentSearchesPreferences

    // Reader & Downloads
    let readerPreferences: ReaderPreferences
    let lendingDownloadManager: LendingDownloadManager
    let inkyomiContentProtection: InkyomiContentProtection

    // Security stores
    let transportSecretStore: LcpTransportSecretStore
    let passphraseManager: LcpPassphraseManager

    private init() {
        let appState = AppState()
        self.appState = appState

        // SwiftData
        do {
            self.modelContainer = try InkyomiModelContainer.create()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Keychain managers
        self.authKeychain = KeychainManager(service: Constants.Keychain.authService)
        self.transportKeychain = KeychainManager(service: Constants.Keychain.transportService)
        self.passphraseKeychain = KeychainManager(service: Constants.Keychain.passphraseService)

        // Auth API (separate client, no auth interceptor)
        let deviceIdProvider: @Sendable () async -> String? = { [weak appState] in
            await MainActor.run { appState?.deviceId }
        }
        self.authAPIService = AuthAPIService(deviceIdProvider: deviceIdProvider)

        // Auth repository. The transport/passphrase keychains and the model
        // container are injected so sign-out can wipe ALL local user data
        // (LCP key material + SwiftData), not just the auth keychain. All
        // three are constructed above, so there is no init/retain cycle.
        self.authRepository = NativeAuthRepository(
            authAPI: authAPIService,
            keychain: authKeychain,
            appState: appState,
            transportKeychain: transportKeychain,
            passphraseKeychain: passphraseKeychain,
            modelContainer: modelContainer
        )

        // Main API client (with auth + device ID interceptors)
        let authRepo = self.authRepository
        self.apiClient = APIClient(
            tokenProvider: { await authRepo.getAccessToken() },
            deviceIdProvider: deviceIdProvider
        )

        // Catalog
        self.catalogAPIService = CatalogAPIService(client: apiClient)
        self.catalogRepository = CatalogRepositoryImpl(api: catalogAPIService)

        // Discovery (browse-hub, trending, related books)
        self.discoveryAPIService = DiscoveryAPIService(client: apiClient)
        self.discoveryRepository = DiscoveryRepositoryImpl(api: discoveryAPIService)

        // Search v2 (FTS + faceted + typeahead)
        self.searchAPIService = SearchAPIService(client: apiClient)
        self.searchRepository = SearchRepositoryImpl(api: searchAPIService)

        // Saved searches CRUD
        self.savedSearchesAPIService = SavedSearchesAPIService(client: apiClient)
        self.savedSearchesRepository = SavedSearchesRepositoryImpl(api: savedSearchesAPIService)

        // Recent search history (UserDefaults-backed; MainActor-isolated)
        self.recentSearches = MainActor.assumeIsolated { RecentSearchesPreferences() }

        // Library
        self.entitlementAPIService = EntitlementAPIService(client: apiClient)
        self.libraryRepository = LibraryRepositoryImpl(entitlementAPI: entitlementAPIService, modelContainer: modelContainer)

        // Device
        self.deviceAPIService = DeviceAPIService(client: apiClient)
        self.deviceRepository = DeviceRepositoryImpl(api: deviceAPIService, appState: appState)

        // Account self-service (GDPR deletion — 30-day grace)
        self.accountAPIService = AccountAPIService(client: apiClient)
        self.accountRepository = AccountRepositoryImpl(api: accountAPIService)

        // Lending
        self.transportSecretStore = LcpTransportSecretStore(keychain: transportKeychain)
        self.passphraseManager = LcpPassphraseManager(keychain: passphraseKeychain)
        self.opdsCatalogAPIService = OpdsCatalogAPIService(client: apiClient)
        self.opdsLendingAPIService = OpdsLendingAPIService(client: apiClient)
        self.lendingRepository = LendingRepositoryImpl(
            catalogAPI: opdsCatalogAPIService,
            api: opdsLendingAPIService,
            transportSecretStore: transportSecretStore,
            modelContainer: modelContainer
        )

        // Telemetry
        self.spanTelemetryAPIService = SpanTelemetryAPIService(client: apiClient)
        self.readerAPIService = ReaderAPIService(client: apiClient)
        self.readerSyncAPIService = ReaderSyncAPIService(client: apiClient)
        self.spanTelemetryRepository = SpanTelemetryRepository(
            modelContainer: modelContainer,
            apiService: spanTelemetryAPIService,
            deviceId: appState.deviceId
        )

        // Downloads & DRM
        self.lendingDownloadManager = LendingDownloadManager()
        self.inkyomiContentProtection = InkyomiContentProtection(
            modelContainer: modelContainer,
            transportSecretStore: transportSecretStore
        )

        // Book repository (downloads, bookmarks, highlights)
        self.bookRepository = BookRepositoryImpl(
            modelContainer: modelContainer,
            apiClient: apiClient,
            entitlementAPI: entitlementAPIService,
            lendingAPI: opdsLendingAPIService,
            lendingDownloadManager: lendingDownloadManager,
            transportSecretStore: transportSecretStore
        )

        // Reader preferences
        self.readerPreferences = MainActor.assumeIsolated { ReaderPreferences() }

        // Storage management + proactive loan renewal
        self.storageRepository = StorageRepository()
        self.loanRenewalCoordinator = LoanRenewalCoordinator(lendingRepository: lendingRepository)

        // Reader-state sync (bookmarks, annotations, position, preferences).
        // MainActor-isolated like ReaderPreferences above. Capture locals so
        // the closure doesn't reference `self` before init completes.
        let readerSyncAPI = self.readerSyncAPIService
        let container = self.modelContainer
        self.readerSyncCoordinator = MainActor.assumeIsolated {
            ReaderSyncCoordinator(api: readerSyncAPI, modelContainer: container)
        }
    }
}
