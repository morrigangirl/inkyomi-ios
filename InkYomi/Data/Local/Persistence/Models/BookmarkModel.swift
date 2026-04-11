import Foundation
import SwiftData

@Model
final class BookmarkModel {
    @Attribute(.unique) var id: String
    var bookId: String
    var locatorJson: String
    var chapterTitle: String?
    var label: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        bookId: String,
        locatorJson: String,
        chapterTitle: String? = nil,
        label: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.locatorJson = locatorJson
        self.chapterTitle = chapterTitle
        self.label = label
        self.createdAt = createdAt
    }

    func toReaderBookmark() -> ReaderBookmark {
        ReaderBookmark(
            id: id,
            bookId: bookId,
            locatorJson: locatorJson,
            chapterTitle: chapterTitle,
            label: label,
            createdAt: createdAt
        )
    }
}
