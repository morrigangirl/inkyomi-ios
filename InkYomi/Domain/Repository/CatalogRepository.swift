import Foundation

protocol CatalogRepository: Sendable {
    func getLandingPage() async throws -> LandingPage
    func getBookDetail(idOrSlug: String) async throws -> BookDetail
    func searchBooks(query: String) async throws -> [Book]
}
