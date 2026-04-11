import Foundation

struct LibraryBook: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let slug: String?
    let authorName: String?
    let coverUrl: String?
    let priceUsd: Double?
    let entitlementType: EntitlementType
    let loanInfo: LoanInfo?
}

enum EntitlementType: String, Sendable {
    case owned
    case borrowed
}
