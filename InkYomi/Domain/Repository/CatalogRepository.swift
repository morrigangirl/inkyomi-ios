import Foundation

protocol CatalogRepository: Sendable {
    func getLandingPage() async throws -> LandingPage
    func getBookDetail(idOrSlug: String) async throws -> BookDetail

    /// Fetch the public Look Inside preview for a book. Returns `nil` when
    /// the backend reports no preview is available (HTTP 404). Other
    /// failures throw.
    func getLookInside(idOrSlug: String) async throws -> LookInsidePreview?
}
