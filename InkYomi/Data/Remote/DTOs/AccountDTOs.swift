import Foundation

/// Request body for `POST /api/data/account/deletion-request`.
/// `reason` is optional free text (the server caps it at 500 chars).
struct AccountDeletionRequestBody: Encodable {
    let reason: String?
}

/// `202` response from a successful deletion request. Timestamps are kept
/// as raw strings (like the app's other DTOs) rather than `Date`, so an
/// unexpected fractional-second format can't fail the whole decode.
struct AccountDeletionRequestResponse: Decodable {
    let graceEndsAt: String
    let booksWithdrawn: Int
    let coAuthorRowsRemoved: Int
}

/// One entry from a `400 blockers_present` body. The server distinguishes
/// `kind == "hard"` (must be resolved first) from `"info"` (advisory).
struct AccountDeletionBlockerDto: Decodable {
    let kind: String
    let code: String
    let message: String
}

/// Body of a `400 { error: "blockers_present", blockers: [...] }` response.
struct AccountDeletionBlockersErrorDto: Decodable {
    let error: String
    let blockers: [AccountDeletionBlockerDto]
}
