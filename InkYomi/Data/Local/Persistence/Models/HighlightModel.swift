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

    init(
        id: String = UUID().uuidString,
        bookId: String,
        locatorJson: String,
        quote: String? = nil,
        colorHex: String = HighlightColor.yellow.rawValue,
        style: String = HighlightStyle.highlight.rawValue,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.locatorJson = locatorJson
        self.quote = quote
        self.colorHex = colorHex
        self.style = style
        self.note = note
        self.createdAt = createdAt
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
