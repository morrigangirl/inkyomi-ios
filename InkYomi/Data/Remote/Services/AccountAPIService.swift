import Foundation

struct AccountAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// Start the 30-day account-deletion grace period. The server throws
    /// `APIError.httpError` for `400` (blockers present) and `409` (already
    /// requested); the repository maps those to domain errors.
    func requestDeletion(reason: String?) async throws -> AccountDeletionRequestResponse {
        try await client.request(Endpoint(
            path: "data/account/deletion-request",
            method: .post,
            body: AccountDeletionRequestBody(reason: reason)
        ))
    }
}
