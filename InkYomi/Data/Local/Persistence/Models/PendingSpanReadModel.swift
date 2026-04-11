import Foundation
import SwiftData

@Model
final class PendingSpanReadModel {
    @Attribute(.unique) var id: String
    var loanId: String
    var accId: String
    var sequenceIndex: Int
    var enteredAt: Date
    var exitedAt: Date?
    var dwellMs: Int64
    var uploaded: Bool

    init(
        id: String = UUID().uuidString,
        loanId: String,
        accId: String,
        sequenceIndex: Int,
        enteredAt: Date,
        exitedAt: Date? = nil,
        dwellMs: Int64 = 0,
        uploaded: Bool = false
    ) {
        self.id = id
        self.loanId = loanId
        self.accId = accId
        self.sequenceIndex = sequenceIndex
        self.enteredAt = enteredAt
        self.exitedAt = exitedAt
        self.dwellMs = dwellMs
        self.uploaded = uploaded
    }
}
