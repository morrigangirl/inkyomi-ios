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

    // MARK: - Server sync bookkeeping
    //
    // All sync fields are optional / defaulted so SwiftData performs a
    // lightweight (additive) migration — no manual migration plan needed.
    //
    // `serverId` is the id returned by the backend once the bookmark has
    // been pushed; nil means "local-only, never confirmed by the server".
    // `needsSync` flags a local create that still has to be POSTed.
    // `pendingDelete` marks a row the user removed locally that still has
    // to be DELETEd server-side before we can drop it from the store.
    var serverId: String?
    var needsSync: Bool = false
    var pendingDelete: Bool = false

    init(
        id: String = UUID().uuidString,
        bookId: String,
        locatorJson: String,
        chapterTitle: String? = nil,
        label: String? = nil,
        createdAt: Date = Date(),
        serverId: String? = nil,
        needsSync: Bool = false,
        pendingDelete: Bool = false
    ) {
        self.id = id
        self.bookId = bookId
        self.locatorJson = locatorJson
        self.chapterTitle = chapterTitle
        self.label = label
        self.createdAt = createdAt
        self.serverId = serverId
        self.needsSync = needsSync
        self.pendingDelete = pendingDelete
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
