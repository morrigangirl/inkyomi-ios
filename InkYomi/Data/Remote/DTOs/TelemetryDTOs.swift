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

// Server expects snake_case on `/api/telemetry/spans`; APIClient's
// JSONEncoder does NOT use convertToSnakeCase, so each request DTO
// supplies explicit CodingKeys (mirrors Android's `@SerialName`).
struct SpanUploadRequest: Encodable {
    let loanId: String
    let deviceId: String
    let clientTimestamp: String
    let clientVersion: String
    let spans: [SpanReadDto]

    enum CodingKeys: String, CodingKey {
        case loanId = "loan_id"
        case deviceId = "device_id"
        case clientTimestamp = "client_timestamp"
        case clientVersion = "client_version"
        case spans
    }
}

struct SpanReadDto: Encodable {
    let accId: String
    let sequenceIndex: Int
    let enteredAt: String
    let exitedAt: String
    let dwellMs: Int64

    enum CodingKeys: String, CodingKey {
        case accId = "acc_id"
        case sequenceIndex = "sequence_index"
        case enteredAt = "entered_at"
        case exitedAt = "exited_at"
        case dwellMs = "dwell_ms"
    }
}

struct SpanUploadResponse: Decodable {
    let ok: Bool?
    let batchId: String?
    let accepted: Int?
    let rejected: Int?
}
