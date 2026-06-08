import Foundation

/// Request body for `POST /api/data/account/deletion-request`.
/// `reason` is optional free text (the server caps it at 500 chars).
struct AccountDeletionRequest: Encodable, Sendable {
    let reason: String?
}

/// 202 response from `deletion-request`. The shared APIClient decoder uses
/// `.convertFromSnakeCase`, so the server's snake_case keys map to these
/// camelCase properties without explicit CodingKeys.
struct AccountDeletionResponse: Decodable, Sendable {
    let graceEndsAt: String
    let booksWithdrawn: Int?
    let coAuthorRowsRemoved: Int?
}

/// A hard blocker the server returns (HTTP 400, `blockers_present`) when the
/// account can't be deleted yet — e.g. pending royalties, an active loan, or
/// an unresolved tax form. Decoded with a dedicated decoder in the view model
/// (the error body, unlike success responses, isn't snake_case-converted).
struct AccountDeletionBlocker: Decodable, Sendable, Identifiable {
    let code: String
    let message: String
    var id: String { code }
}

/// Shape of the 400 error body: `{ "error": "blockers_present", "blockers": [...] }`.
struct AccountDeletionBlockersError: Decodable, Sendable {
    let error: String?
    let blockers: [AccountDeletionBlocker]?
}
