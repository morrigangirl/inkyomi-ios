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
    let opdsCatalogAPIService: OpdsCatalogAPIService
    let opdsLendingAPIService: OpdsLendingAPIService
    let spanTelemetryAPIService: SpanTelemetryAPIService
    let readerAPIService: ReaderAPIService

    // Repositories
    let authRepository: NativeAuthRepository
    let catalogRepository: CatalogRepositoryImpl
    let discoveryRepository: DiscoveryRepositoryImpl
    let searchRepository: SearchRepositoryImpl
    let savedSearchesRepository: SavedSearchesRepositoryImpl
    let libraryRepository: LibraryRepositoryImpl
    let deviceRepository: DeviceRepositoryImpl
    let lendingRepository: LendingRepositoryImpl
    let spanTelemetryRepository: SpanTelemetryRepository
    let bookRepository: BookRepositoryImpl
    let storageRepository: StorageRepository
    let loanRenewalCoordinator: LoanRenewalCoordinator

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

        // Auth repository
        self.authRepository = NativeAuthRepository(
            authAPI: authAPIService,
            keychain: authKeychain,
            appState: appState
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
        // `clientVersion` is read from Info.plist's CFBundleShortVersionString
        // (which is $(MARKETING_VERSION) from project.yml) so server logs
        // can tie a span batch to a known release.
        let clientVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
        self.spanTelemetryRepository = SpanTelemetryRepository(
            modelContainer: modelContainer,
            api: spanTelemetryAPIService,
            appState: appState,
            clientVersion: clientVersion
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
    }
}
