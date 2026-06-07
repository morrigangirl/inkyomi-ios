import Foundation

/// A reason the account can't be deleted yet (e.g. an active loan to
/// return). Surfaced to the user so they can resolve it and retry.
struct AccountDeletionBlocker: Identifiable, Sendable {
    let code: String
    let message: String
    var id: String { code }
}

/// Outcome of a successful deletion request — the account is now in its
/// 30-day grace window and locked server-side.
struct AccountDeletionOutcome: Sendable {
    /// ISO-8601 timestamp the grace window ends (raw server string).
    let graceEndsAt: String
    let booksWithdrawn: Int
}

enum AccountDeletionError: Error, LocalizedError {
    /// Hard blockers must be resolved before deletion can proceed.
    case blocked([AccountDeletionBlocker])
    /// A deletion is already pending for this account.
    case alreadyPending
    case server(String)

    var errorDescription: String? {
        switch self {
        case .blocked: "Your account can't be deleted yet."
        case .alreadyPending: "Your account is already scheduled for deletion."
        case .server(let message): message
        }
    }
}

protocol AccountRepository: Sendable {
    /// Request account deletion, starting the 30-day grace period. On
    /// success the account is locked server-side, so the caller should sign
    /// out. Throws `AccountDeletionError` for blockers / already-pending.
    func requestAccountDeletion(reason: String?) async throws -> AccountDeletionOutcome
}
