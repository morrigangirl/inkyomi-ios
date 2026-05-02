import Foundation

struct CatalogRepositoryImpl: CatalogRepository, Sendable {
    private let api: CatalogAPIService

    init(api: CatalogAPIService) {
        self.api = api
    }

    func getLandingPage() async throws -> LandingPage {
        try await api.getLandingPage().toDomain()
    }

    func getBookDetail(idOrSlug: String) async throws -> BookDetail {
        let response = try await api.getBookDetail(idOrSlug: idOrSlug)
        return response.toDomain()
    }

    func searchBooks(query: String) async throws -> [Book] {
        let response = try await api.search(query: query)
        return response.data.map { $0.toDomain() }
    }
}

/// Mapper extracted to a top-level extension so other repositories
/// (notably `DiscoveryRepositoryImpl.getDiscoverHome`) can reuse it
/// when an embedded `LandingPageResponse` arrives as part of a
/// composite payload.
extension LandingPageResponse {
    func toDomain() -> LandingPage {
        LandingPage(
            shelves: shelves.map { $0.toDomain() },
            heroSlides: heroSlides.map { $0.toDomain() },
            categories: categories.map { $0.toDomain() }
        )
    }
}
