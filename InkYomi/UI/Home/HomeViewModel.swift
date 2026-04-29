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
    private var modelContext: ModelContext?

    func configure(
        catalogRepository: any CatalogRepository,
        discoveryRepository: any DiscoveryRepository,
        libraryRepository: any LibraryRepository,
        modelContext: ModelContext
    ) {
        self.catalogRepository = catalogRepository
        self.discoveryRepository = discoveryRepository
        self.libraryRepository = libraryRepository
        self.modelContext = modelContext
    }

    func loadLandingPage() async {
        guard let catalogRepository else { return }
        isLoading = true
        error = nil
        // Fan out the three home-feed network calls in parallel.
        // Trending + browse-hub failures are swallowed so an outage on
        // one new endpoint doesn't blank the Home screen.
        async let landing: LandingPage? = try? catalogRepository.getLandingPage()
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
        isLoading = false
        loadContinueReading()
    }

    func refresh() async {
        guard let catalogRepository else { return }
        isRefreshing = true
        async let landing: LandingPage? = try? catalogRepository.getLandingPage()
        async let trendingFeed: [TrendingBook] = (try? await discoveryRepository?.getTrending(limit: 12)) ?? []
        async let browseHubGroups: [BrowseHubGroup] = (try? await discoveryRepository?.getBrowseHub()) ?? []

        let (landingResolved, trendingResolved, hubResolved) = await (landing, trendingFeed, browseHubGroups)
        if let landingResolved { landingPage = landingResolved }
        trending = trendingResolved
        browseHub = hubResolved
        isRefreshing = false
        loadContinueReading()
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

    private func loadContinueReading() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.lastOpenedAt != nil && $0.progressPercent < 0.98 },
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        guard let books = try? modelContext.fetch(descriptor) else { return }
        let items = Array(books.prefix(Constants.continueReadingLimit))

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
            loadContinueReading()
        }
    }
}
