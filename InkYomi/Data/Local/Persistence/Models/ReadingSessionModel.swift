import Foundation
import SwiftData

@Model
final class ReadingSessionModel {
    @Attribute(.unique) var id: String
    var bookId: String
    var startedAt: Date
    var endedAt: Date?

    init(
        id: String = UUID().uuidString,
        bookId: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
