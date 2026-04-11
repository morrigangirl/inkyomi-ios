import Foundation
import SwiftData

@Model
final class AccountingManifestModel {
    @Attribute(.unique) var loanId: String
    var bookId: String
    var normalizedPageWords: Int
    var spansJson: String // JSON array of { accId, sequenceIndex, wordCount }
    var fetchedAt: Date

    init(
        loanId: String,
        bookId: String,
        normalizedPageWords: Int,
        spansJson: String,
        fetchedAt: Date = Date()
    ) {
        self.loanId = loanId
        self.bookId = bookId
        self.normalizedPageWords = normalizedPageWords
        self.spansJson = spansJson
        self.fetchedAt = fetchedAt
    }
}
