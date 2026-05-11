import Foundation
import Observation

@MainActor @Observable
final class SearchResultsViewModel {
    var query: String = ""
    var filters: SearchFilters = SearchFilters()
    var sort: SearchSortOrder = .relevance
    var isLoading: Bool = false
    var books: [SearchResultBook] = []
    var total: Int = 0
    var facets: [FacetGroup] = []
    var spellSuggest: String?
    var errorMessage: String?

    /// Pagination state. `currentPage` is the most recent page that
    /// successfully loaded; `isLoadingMore` is the post-first-page
    /// fetch flag (separate from `isLoading` so the UI doesn't blank
    /// the existing grid while appending).
    var currentPage: Int = 1
    var isLoadingMore: Bool = false
    var hasMore: Bool = false

    static let limit: Int = 24

    private var repository: (any SearchRepository)?
    private var savedSearchesRepository: (any SavedSearchesRepository)?
    private var initialized: Bool = false

    func configure(
        repository: any SearchRepository,
        savedSearchesRepository: (any SavedSearchesRepository)? = nil
    ) {
        self.repository = repository
        self.savedSearchesRepository = savedSearchesRepository
    }

    /// Apply the initial search context. Called once from
    /// `SearchResultsView` with whatever pre-applied filter the
    /// navigator passed (e.g. tagType+tagSlug from a browse-hub tile,
    /// or just a free-text query from the search bar, or a
    /// `savedSearchId` from the saved-searches list).
    func initialize(
        query: String? = nil,
        prefilledTagType: TagType? = nil,
        prefilledTagSlug: String? = nil,
        prefilledTagFilters: [TagType: [String]]? = nil,
        authorId: String? = nil,
        seriesId: String? = nil,
        savedSearchId: String? = nil
    ) async {
        guard !initialized else { return }
        initialized = true

        // If the navigator passed a savedSearchId, fetch the saved
        // search and apply its query+filters+sort directly. Falls
        // through to the default-init branch on lookup failure so the
        // user still sees a valid (empty) state rather than a hang.
        if let savedSearchId,
           let repo = savedSearchesRepository,
           let all = try? await repo.list(),
           let saved = all.first(where: { $0.id == savedSearchId }) {
            self.query = saved.query ?? ""
            self.filters = saved.filters
            self.sort = saved.sort
                ?? (saved.query?.isEmpty == false ? .relevance : .newest)
            await runSearch()
            return
        }

        var filters = SearchFilters()
        if let prefilledTagFilters, !prefilledTagFilters.isEmpty {
            // Multi-axis (Browse Hub "Browse Views" tile) takes priority:
            // server already resolved the category into per-type slug
            // buckets, so we apply them directly. Single-axis params are
            // ignored in this case.
            filters.tagSlugs = prefilledTagFilters.filter { !$0.value.isEmpty }
        } else if let prefilledTagType, let slug = prefilledTagSlug, !slug.isEmpty {
            filters.tagSlugs = [prefilledTagType: [slug]]
        }
        filters.authorId = authorId
        filters.seriesId = seriesId
        // Default to NEWEST when there's no free-text query: a
        // tag-filtered or entity-filtered browse view has no FTS
        // context for relevance ranking, so newest-first is the most
        // useful ordering. RELEVANCE only when there's a `q` to rank
        // against. (Pearlescent-dream's no-`q` relevance bug —
        // `bp.score` referenced without joining `book_popularity` —
        // was fixed in commit `aef4be5` and is live in prod.)
        let initialSort: SearchSortOrder
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            initialSort = .relevance
        } else {
            initialSort = .newest
        }
        self.query = query ?? ""
        self.filters = filters
        self.sort = initialSort
        await runSearch()
    }

    /// Save the current query+filters+sort as a named saved search.
    /// Failure is silent — user keeps results.
    func saveCurrentSearch(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let repo = savedSearchesRepository else { return }
        _ = try? await repo.create(
            name: trimmed,
            query: query.isEmpty ? nil : query,
            filters: filters,
            sort: sort
        )
    }

    func setSort(_ newSort: SearchSortOrder) async {
        guard newSort != sort else { return }
        sort = newSort
        await runSearch()
    }

    func setQuery(_ newQuery: String) async {
        guard newQuery != query else { return }
        query = newQuery
        await runSearch()
    }

    // MARK: - Filter manipulation

    func toggleTagFilter(type: TagType, slug: String) {
        filters = filters.toggleTag(type: type, slug: slug)
    }

    func setPriceRange(_ minUsd: Double?, _ maxUsd: Double?) {
        filters.priceMin = minUsd
        filters.priceMax = maxUsd
    }

    func setRatingMin(_ rating: Double?) {
        filters.ratingMin = rating
    }

    /// Re-run the search with the user's filter changes (called from
    /// the Apply button). */
    func applyFilters() async { await runSearch() }

    func clearFilters() async {
        filters = SearchFilters()
        await runSearch()
    }

    func removeTagFilter(type: TagType, slug: String) async {
        filters = filters.toggleTag(type: type, slug: slug)
        await runSearch()
    }

    func removeAuthor() async {
        filters.authorId = nil
        await runSearch()
    }

    func removeSeries() async {
        filters.seriesId = nil
        await runSearch()
    }

    func removePriceRange() async {
        filters.priceMin = nil
        filters.priceMax = nil
        await runSearch()
    }

    func removeRating() async {
        filters.ratingMin = nil
        await runSearch()
    }

    // MARK: - Pagination

    /// Fetch the next page and append. No-op if a page fetch is already
    /// in flight or if we've already pulled everything (`hasMore=false`).
    /// Errors append silently — the user keeps the existing results and
    /// a tiny spinner just disappears.
    func loadMore() async {
        guard let repository, !isLoading, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let results = try await repository.search(
                query: query.isEmpty ? nil : query,
                filters: filters,
                sort: sort,
                page: nextPage,
                limit: Self.limit
            )
            let merged = books + results.books
            isLoadingMore = false
            books = merged
            total = results.total
            currentPage = nextPage
            hasMore = merged.count < results.total && !results.books.isEmpty
        } catch {
            isLoadingMore = false
        }
    }

    private func runSearch() async {
        guard let repository else { return }
        isLoading = true
        errorMessage = nil
        do {
            let results = try await repository.search(
                query: query.isEmpty ? nil : query,
                filters: filters,
                sort: sort,
                page: 1,
                limit: Self.limit
            )
            isLoading = false
            books = results.books
            total = results.total
            facets = results.facets
            sort = results.sort
            spellSuggest = results.spellSuggest
            currentPage = 1
            hasMore = results.books.count < results.total
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}
