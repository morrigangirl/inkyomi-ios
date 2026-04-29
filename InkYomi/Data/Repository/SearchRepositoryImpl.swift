import Foundation

struct SearchRepositoryImpl: SearchRepository, Sendable {
    private let api: SearchAPIService

    init(api: SearchAPIService) {
        self.api = api
    }

    func search(
        query: String?,
        filters: SearchFilters,
        sort: SearchSortOrder,
        page: Int,
        limit: Int
    ) async throws -> SearchResults {
        let response = try await api.search(
            query: query,
            sort: sort,
            page: page,
            limit: limit,
            filters: filters
        )
        return response.toDomain()
    }

    func suggest(query: String) async throws -> SuggestResults {
        let response = try await api.suggest(query: query)
        return response.toDomain()
    }
}
