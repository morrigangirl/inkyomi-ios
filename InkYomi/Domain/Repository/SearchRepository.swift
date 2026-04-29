import Foundation

protocol SearchRepository: Sendable {
    func search(
        query: String?,
        filters: SearchFilters,
        sort: SearchSortOrder,
        page: Int,
        limit: Int
    ) async throws -> SearchResults

    func suggest(query: String) async throws -> SuggestResults
}
