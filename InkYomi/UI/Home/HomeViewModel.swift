import Foundation
import Observation
import SwiftData

struct ContinueReadingItem: Identifiable, Sendable {
    let bookId: String
    let title: String
    let authorName: String?
    let coverUrl: String?
    let progressPercent: Float

    var id: String { bookId }
}

@MainActor @Observable
final class HomeViewModel {
    var landingPage: LandingPage?
    var isLoading = false
    var isRefreshing = false
    var error: String?
    var searchQuery = ""
    var searchResults: [Book]?
    var isSearching = false
    var continueReading: [ContinueReadingItem] = []

    /// Phase 1 of the discovery revamp: top-line trending feed,
    /// rendered as a single horizontal row above Featured shelves.
    var trending: [TrendingBook] = []
    /// Phase 1 of the discovery revamp: server-driven groups of
    /// "discovery tiles" (genre / mood / trope / identity / browse-views)
    /// rendered as the Browse Hub section below shelves.
    var browseHub: [BrowseHubGroup] = []

    private var searchTask: Task<Void, Never>?
    private var catalogRepository: (any CatalogRepository)?
    private var discoveryRepository: (any DiscoveryRepository)?
    private var libraryRepository: (any LibraryRepository)?
    private var lendingRepository: (any LendingRepository)?
    private var modelContext: ModelContext?

    func configure(
        catalogRepository: any CatalogRepository,
        discoveryRepository: any DiscoveryRepository,
        libraryRepository: any LibraryRepository,
        lendingRepository: any LendingRepository,
        modelContext: ModelContext
    ) {
        self.catalogRepository = catalogRepository
        self.discoveryRepository = discoveryRepository
        self.libraryRepository = libraryRepository
        self.lendingRepository = lendingRepository
        self.modelContext = modelContext
    }

    func loadLandingPage() async {
        guard catalogRepository != nil else { return }
        isLoading = true
        error = nil
        await fetchHomeData()
        isLoading = false
        await loadContinueReading()
    }

    func refresh() async {
        guard catalogRepository != nil else { return }
        isRefreshing = true
        await fetchHomeData()
        isRefreshing = false
        await loadContinueReading()
    }

    /// Fetch the Home payload. Tries the combined `/api/data/discover/home`
    /// endpoint first (one round trip) and falls back to the legacy
    /// three-call fanout on failure (older backends 404 the route).
    ///
    /// In the fanout fallback, landing-page is the only "must succeed"
    /// call; trending + browse-hub failures are swallowed so an outage
    /// on one new endpoint doesn't blank the whole Home screen.
    private func fetchHomeData() async {
        // Combined endpoint — one round trip. Backends predating the
        // discover/home commit return 404; we treat any failure as a
        // signal to fall back so the user never sees a blank Home just
        // because the new endpoint isn't deployed yet.
        if let combined = try? await discoveryRepository?.getDiscoverHome(trendingLimit: 12) {
            landingPage = combined.landingPage
            browseHub = combined.browseHub
            trending = combined.trending
            return
        }

        // Legacy fanout — three parallel calls. Used when the combined
        // endpoint is unavailable; behaviorally identical to the
        // pre-uplift code path.
        async let landing: LandingPage? = try? catalogRepository?.getLandingPage()
        async let trendingFeed: [TrendingBook] = (try? await discoveryRepository?.getTrending(limit: 12)) ?? []
        async let browseHubGroups: [BrowseHubGroup] = (try? await discoveryRepository?.getBrowseHub()) ?? []

        let (landingResolved, trendingResolved, hubResolved) = await (landing, trendingFeed, browseHubGroups)
        if let landingResolved {
            landingPage = landingResolved
        } else {
            error = "Failed to load home"
        }
        trending = trendingResolved
        browseHub = hubResolved
    }

    func onSearchQueryChanged(_ query: String) {
        searchQuery = query
        searchTask?.cancel()

        if query.isEmpty {
            clearSearch()
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(Constants.searchDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            await searchBooks(query: query)
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = nil
        isSearching = false
    }

    private func searchBooks(query: String) async {
        guard let catalogRepository else { return }
        isSearching = true
        do {
            searchResults = try await catalogRepository.searchBooks(query: query)
        } catch {
            if !Task.isCancelled {
                searchResults = []
            }
        }
        isSearching = false
    }

    private func loadContinueReading() async {
        guard let modelContext else { return }

        // Local candidates: books the user has actually opened and
        // hasn't finished. We persist these locally so reading state
        // survives offline / fresh launches, but the rail must
        // additionally pass an entitlement check (below) so a book
        // the user no longer has access to — unpublished, refunded,
        // returned, expired, or revoked — silently drops out.
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.lastOpenedAt != nil && $0.progressPercent < 0.98 },
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        guard let candidates = try? modelContext.fetch(descriptor) else { return }

        // Pull a fresh view of the OPDS lending shelf before reading
        // the local loan cache. Without this, a loan the server has
        // since revoked / returned / unpublished still shows up as
        // "active" locally and the filter below would let the book
        // stay in the Continue Reading rail. syncShelf reconciles
        // (vanished loans → returned + EPUB + secret cleanup) so
        // getActiveLoans returns current truth. Best-effort —
        // network failure falls through to whatever we already had
        // cached, so the rail still loads offline.
        try? await lendingRepository?.syncShelf()

        // Cross-reference candidates against the user's current
        // accessible bookIds: owned (server entitlements) ∪ active or
        // ready borrowed loans (local LoanCacheModel — now fresh
        // after the syncShelf above). On any network/data failure we
        // fall through to the unfiltered candidate list so a flaky
        // connection doesn't blank the rail; the next refresh will
        // tighten it.
        let filtered: [CachedBookModel]
        if let owned = try? await libraryRepository?.getOwnedBooks(),
           let active = try? await lendingRepository?.getActiveLoans() {
            let accessible = Set(owned.map { $0.id })
                .union(active.map { $0.bookId })
            filtered = candidates.filter { accessible.contains($0.bookId) }
        } else {
            filtered = candidates
        }

        let items = Array(filtered.prefix(Constants.continueReadingLimit))

        // Backfill missing cover URLs from the library API
        let missingCovers = items.filter { $0.coverUrl == nil }
        if !missingCovers.isEmpty {
            Task {
                await backfillCovers(for: missingCovers)
            }
        }

        continueReading = items.map {
            ContinueReadingItem(
                bookId: $0.bookId,
                title: $0.title,
                authorName: $0.authorName,
                coverUrl: $0.coverUrl,
                progressPercent: $0.progressPercent
            )
        }
    }

    private func backfillCovers(for books: [CachedBookModel]) async {
        guard let libraryRepository, let modelContext else { return }
        guard let ownedBooks = try? await libraryRepository.getOwnedBooks() else { return }
        let coverMap = Dictionary(ownedBooks.compactMap { b in
            b.coverUrl.map { (b.id, $0) }
        }, uniquingKeysWith: { first, _ in first })

        var updated = false
        for cached in books {
            if let coverUrl = coverMap[cached.bookId] {
                cached.coverUrl = coverUrl
                if cached.title.isEmpty, let lib = ownedBooks.first(where: { $0.id == cached.bookId }) {
                    cached.title = lib.title
                    cached.authorName = lib.authorName
                }
                updated = true
            }
        }
        if updated {
            try? modelContext.save()
            await loadContinueReading()
        }
    }
}
