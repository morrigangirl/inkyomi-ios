import Foundation

struct EntitlementAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getMyBooks() async throws -> EntitlementBooksResponse {
        try await client.request(Endpoint(path: "data/entitlements/me/books"))
    }
}
