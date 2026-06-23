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
    /// Stable per-upload-batch idempotency id. Assigned at drain time and
    /// REUSED on retry (the row keeps it until a confirmed 2xx deletes the row),
    /// so a resend after a lost ACK carries the same `client_batch_id` and the
    /// server dedups it (migration 159). nil = not yet assigned to a batch.
    var batchId: String?

    init(
        id: String = UUID().uuidString,
        loanId: String,
        accId: String,
        sequenceIndex: Int,
        enteredAt: Date,
        exitedAt: Date? = nil,
        dwellMs: Int64 = 0,
        uploaded: Bool = false,
        batchId: String? = nil
    ) {
        self.id = id
        self.loanId = loanId
        self.accId = accId
        self.sequenceIndex = sequenceIndex
        self.enteredAt = enteredAt
        self.exitedAt = exitedAt
        self.dwellMs = dwellMs
        self.uploaded = uploaded
        self.batchId = batchId
    }
}
