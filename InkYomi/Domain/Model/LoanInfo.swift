import Foundation

struct LoanInfo: Identifiable, Equatable, Sendable {
    let loanId: String
    let licenseId: String
    let bookId: String
    var title: String?
    var authorName: String?
    var coverUrl: String?
    let status: LoanStatus
    let dueAt: Date?
    let renewedCount: Int
    let maxRenewals: Int

    var id: String { loanId }

    var canRenew: Bool {
        status == .active && renewedCount < maxRenewals
    }

    var isExpired: Bool {
        guard let dueAt else { return false }
        return Date() > dueAt
    }

    var isTerminal: Bool {
        switch status {
        case .returned, .cancelled, .revoked, .expired:
            return true
        case .ready, .active:
            return false
        }
    }
}

enum LoanStatus: String, Codable, Sendable {
    case ready
    case active
    case returned
    case cancelled
    case revoked
    case expired
}
