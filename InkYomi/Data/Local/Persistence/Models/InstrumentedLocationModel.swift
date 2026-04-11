import Foundation
import SwiftData

@Model
final class InstrumentedLocationModel {
    @Attribute(.unique) var id: String
    var bookId: String
    var label: String
    var href: String
    var progressionStart: Double
    var progressionEnd: Double

    init(
        id: String = UUID().uuidString,
        bookId: String,
        label: String,
        href: String,
        progressionStart: Double,
        progressionEnd: Double
    ) {
        self.id = id
        self.bookId = bookId
        self.label = label
        self.href = href
        self.progressionStart = progressionStart
        self.progressionEnd = progressionEnd
    }
}
