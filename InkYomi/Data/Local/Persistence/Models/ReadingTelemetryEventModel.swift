import Foundation
import SwiftData

@Model
final class ReadingTelemetryEventModel {
    @Attribute(.unique) var id: String
    var sessionId: String
    var bookId: String
    var type: String
    var durationMs: Int64

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        bookId: String,
        type: String,
        durationMs: Int64
    ) {
        self.id = id
        self.sessionId = sessionId
        self.bookId = bookId
        self.type = type
        self.durationMs = durationMs
    }
}
