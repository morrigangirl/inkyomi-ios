import Foundation

struct AccountingManifestResponse: Decodable {
    let bookId: String
    let spans: [AccountingSpanDto]
    let normalizedPageWords: Int
}

struct AccountingSpanDto: Decodable {
    let accId: String
    let sequenceIndex: Int
    let wordCount: Int
}

struct SpanUploadRequest: Encodable {
    let loanId: String
    let deviceId: String
    let clientTimestamp: String
    let clientVersion: String
    let spans: [SpanReadDto]
}

struct SpanReadDto: Encodable {
    let accId: String
    let sequenceIndex: Int
    let enteredAt: String
    let exitedAt: String
    let dwellMs: Int64
}

struct SpanUploadResponse: Decodable {
    let ok: Bool?
    let batchId: String?
    let accepted: Int?
    let rejected: Int?
}
