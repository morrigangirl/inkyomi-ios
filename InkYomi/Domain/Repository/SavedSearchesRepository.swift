import Foundation

/// CRUD over the user's saved searches. Backed by
/// `/api/data/saved-searches`. UI surface: a "Save" toolbar button in
/// the `FiltersSheet` of `SearchResultsView`, and a "Saved searches"
/// section in `SearchView`'s empty-query state above the existing
/// recent-search list.
protocol SavedSearchesRepository: Sendable {
    func list() async throws -> [SavedSearch]

    func create(
        name: String,
        query: String?,
        filters: SearchFilters,
        sort: SearchSortOrder?
    ) async throws -> SavedSearch

    func update(
        id: String,
        name: String?,
        query: String?,
        filters: SearchFilters?,
        sort: SearchSortOrder?
    ) async throws -> SavedSearch

    func delete(id: String) async throws
}
