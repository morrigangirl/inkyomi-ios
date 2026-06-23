import Foundation

// Response DTOs: the APIClient decoder uses `.convertFromSnakeCase`, so these
// camelCase properties decode from the server's snake_case automatically — do
// NOT add snake_case CodingKeys here (it would double-convert and break decode).

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

struct SpanUploadResponse: Decodable {
    let ok: Bool?
    let batchId: String?
    let accepted: Int?
    let rejected: Int?
}

// Request DTOs: the APIClient encoder does NOT convert to snake_case, so these
// MUST declare explicit snake_case CodingKeys (the server destructures
// `loan_id`, `device_id`, `acc_id`, etc. — see services/app-api/src/routes/
// telemetry.ts POST /spans). Date fields are encoded as ISO-8601 strings by the
// encoder's `.iso8601` strategy; optional dates are omitted when nil.

struct SpanUploadRequest: Encodable {
    let loanId: String
    let deviceId: String
    let clientTimestamp: Date
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
    let enteredAt: Date?
    let exitedAt: Date?
    let dwellMs: Int64

    enum CodingKeys: String, CodingKey {
        case accId = "acc_id"
        case sequenceIndex = "sequence_index"
        case enteredAt = "entered_at"
        case exitedAt = "exited_at"
        case dwellMs = "dwell_ms"
    }
}
