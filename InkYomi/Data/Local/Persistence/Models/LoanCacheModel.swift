import Foundation
import SwiftData

@Model
final class LoanCacheModel {
    @Attribute(.unique) var loanId: String
    var licenseId: String
    var bookId: String
    var bookTitle: String?
    var authorName: String?
    var coverUrl: String?
    var status: String // LoanStatus raw value
    var dueAt: Date?
    var renewedCount: Int
    var maxRenewals: Int
    var borrowedAt: Date?
    var returnedAt: Date?

    init(
        loanId: String,
        licenseId: String,
        bookId: String,
        bookTitle: String? = nil,
        authorName: String? = nil,
        coverUrl: String? = nil,
        status: String = "active",
        dueAt: Date? = nil,
        renewedCount: Int = 0,
        maxRenewals: Int = 2,
        borrowedAt: Date? = nil
    ) {
        self.loanId = loanId
        self.licenseId = licenseId
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.authorName = authorName
        self.coverUrl = coverUrl
        self.status = status
        self.dueAt = dueAt
        self.renewedCount = renewedCount
        self.maxRenewals = maxRenewals
        self.borrowedAt = borrowedAt
    }

    func toLoanInfo() -> LoanInfo {
        LoanInfo(
            loanId: loanId,
            licenseId: licenseId,
            bookId: bookId,
            title: bookTitle,
            authorName: authorName,
            coverUrl: coverUrl,
            status: LoanStatus(rawValue: status) ?? .active,
            dueAt: dueAt,
            renewedCount: renewedCount,
            maxRenewals: maxRenewals
        )
    }
}
