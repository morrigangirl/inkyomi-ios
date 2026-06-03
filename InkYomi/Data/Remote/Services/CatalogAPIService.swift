import Foundation

struct CatalogAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getLandingPage() async throws -> LandingPageResponse {
        try await client.request(Endpoint(path: "data/books/landing-page"))
    }

    func getBookDetail(idOrSlug: String) async throws -> BookDetailResponse {
        try await client.request(Endpoint(path: "data/books/\(idOrSlug)"))
    }
}
