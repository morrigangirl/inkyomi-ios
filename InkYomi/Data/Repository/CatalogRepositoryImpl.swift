import Foundation

struct CatalogRepositoryImpl: CatalogRepository, Sendable {
    private let api: CatalogAPIService

    init(api: CatalogAPIService) {
        self.api = api
    }

    func getLandingPage() async throws -> LandingPage {
        let response = try await api.getLandingPage()
        return LandingPage(
            shelves: response.shelves.map { $0.toDomain() },
            heroSlides: response.heroSlides.map { $0.toDomain() },
            categories: response.categories.map { $0.toDomain() }
        )
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
