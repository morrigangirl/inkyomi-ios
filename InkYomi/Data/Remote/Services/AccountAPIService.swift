import Foundation

/// Self-service account lifecycle (GDPR Article 17 right-to-erasure), backed by
/// the authenticated API client. Lets the user initiate deletion entirely
/// in-app, as required by App Store Review Guideline 5.1.1(v).
struct AccountAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// Starts the 30-day deletion grace clock. Throws
    /// `APIError.httpError(400, …)` carrying a `blockers_present` body when the
    /// account still has hard blockers, or `httpError(409, …)` if a deletion is
    /// already pending.
    func requestDeletion(reason: String?) async throws -> AccountDeletionResponse {
        try await client.request(Endpoint(
            path: "data/account/deletion-request",
            method: .post,
            body: AccountDeletionRequest(reason: reason)
        ))
    }
}
