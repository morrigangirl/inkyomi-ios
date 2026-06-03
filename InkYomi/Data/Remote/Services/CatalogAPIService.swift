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

    /// Public (no-auth) Look Inside preview. The backend returns 404 when
    /// no preview is available, surfaced here as
    /// `APIError.httpError(statusCode: 404, …)` for the caller to map to a
    /// "no preview" state.
    func getLookInside(idOrSlug: String) async throws -> LookInsidePreviewResponse {
        try await client.request(Endpoint(path: "data/books/\(idOrSlug)/look-inside"))
    }
}
