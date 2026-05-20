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
    // `authRepository` is the active repo for this launch — could be
    // legacy NativeAuthRepository (lazy-transition users) or the new
    // KeycloakAuthRepository (OAuth users / fresh installs). The
    // coordinator made the choice in init; consumers should treat it
    // as protocol-level.
    let authRepository: any AuthRepository
    /// Always-present Keycloak repo. Used directly by the OAuth
    /// login button + `InkYomiApp.onOpenURL` callback dispatch.
    let keycloakAuthRepository: KeycloakAuthRepository
    /// The migration coordinator. Holds the bounce-to-OAuth logic.
    let authMigrationCoordinator: AuthMigrationCoordinator
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

        // Auth repositories
        // The legacy native repo always exists so the lazy-transition
        // code path can run. The Keycloak repo always exists so the
        // OAuth login button + onOpenURL callback have something to
        // call. The migration coordinator picks which one is "active"
        // for this launch based on which credentials are present in
        // the Keychain.
        let native = NativeAuthRepository(
            authAPI: authAPIService,
            keychain: authKeychain,
            appState: appState
        )
        let keycloak = KeycloakAuthRepository(
            keychain: authKeychain,
            appState: appState
        )
        self.keycloakAuthRepository = keycloak

        let coordinator = AuthMigrationCoordinator(
            keycloak: keycloak,
            native: native,
            authKeychain: authKeychain
        )
        self.authMigrationCoordinator = coordinator
        self.authRepository = coordinator.active

        // Wire the terminal-failure hooks so any refresh death — from
        // either repo — funnels through the coordinator's wipe +
        // bounce. Both onTerminalFailure properties are
        // `nonisolated(unsafe)` so this synchronous assignment is
        // valid; the hooks themselves are only invoked from inside
        // their owning actor.
        native.onTerminalFailure = { [weak coordinator] in
            await coordinator?.bounceToOAuth(reason: "NativeAuthRepository terminal refresh failure")
        }
        keycloak.onTerminalFailure = { [weak coordinator] in
            await coordinator?.bounceToOAuth(reason: "KeycloakAuthRepository OIDAuthState terminal error")
        }

        // Main API client (with auth + device ID interceptors). The
        // bearer token routes through whichever repo the coordinator
        // selected; both implement `AuthRepository.getAccessToken`.
        let activeRepo = coordinator.active
        self.apiClient = APIClient(
            tokenProvider: { await activeRepo.getAccessToken() },
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
        // Build the download manager up-front so the lending repository
        // can use it for cache cleanup on explicit return / server
        // reconciliation. The book repository binds to the same
        // instance below — there's only ever one borrowed-EPUBs
        // directory and one in-flight download path.
        self.lendingDownloadManager = LendingDownloadManager()
        self.lendingRepository = LendingRepositoryImpl(
            catalogAPI: opdsCatalogAPIService,
            api: opdsLendingAPIService,
            transportSecretStore: transportSecretStore,
            lendingDownloadManager: lendingDownloadManager,
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
        // lendingDownloadManager was constructed up-front (above) so
        // the lending repository could bind to it for cache cleanup.
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

        // All stored properties are now assigned — hand the
        // coordinator a back-reference so it can drive UserDataWipe
        // on bounce-to-OAuth.
        coordinator.attachContainer(self)
    }
}
