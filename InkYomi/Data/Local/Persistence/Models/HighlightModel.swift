import Foundation
import SwiftData

@Model
final class HighlightModel {
    @Attribute(.unique) var id: String
    var bookId: String
    var locatorJson: String
    var quote: String?
    var colorHex: String
    var style: String // HighlightStyle raw value
    var note: String?
    var createdAt: Date

    // MARK: - Server sync bookkeeping
    //
    // Additive optional / defaulted fields → SwiftData lightweight
    // migration, no manual migration plan.
    //
    // `serverId` is the backend annotation id once pushed.
    // `updatedAt` drives last-write-wins reconciliation against the
    // server's `updated_at`. `needsSync` flags a local create/edit that
    // still has to be pushed. `pendingDelete` marks a removed annotation
    // awaiting a server DELETE.
    var serverId: String?
    var updatedAt: Date = Date()
    var needsSync: Bool = false
    var pendingDelete: Bool = false

    init(
        id: String = UUID().uuidString,
        bookId: String,
        locatorJson: String,
        quote: String? = nil,
        colorHex: String = HighlightColor.yellow.rawValue,
        style: String = HighlightStyle.highlight.rawValue,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        serverId: String? = nil,
        needsSync: Bool = false,
        pendingDelete: Bool = false
    ) {
        self.id = id
        self.bookId = bookId
        self.locatorJson = locatorJson
        self.quote = quote
        self.colorHex = colorHex
        self.style = style
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverId = serverId
        self.needsSync = needsSync
        self.pendingDelete = pendingDelete
    }

    func toReaderHighlight() -> ReaderHighlight {
        ReaderHighlight(
            id: id,
            bookId: bookId,
            locatorJson: locatorJson,
            quote: quote,
            colorHex: colorHex,
            style: HighlightStyle(rawValue: style) ?? .highlight,
            note: note,
            createdAt: createdAt
        )
    }
}
