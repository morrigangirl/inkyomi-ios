import Foundation

/// Wire DTOs for `/api/data/saved-searches`. The `filters` field is
/// decoded as a free-form dictionary (`AnyJSONValue` map) because the
/// backend stores the blob opaquely; the repository layer maps it into
/// a typed `SearchFilters` for use by the UI.

struct SavedSearchDto: Decodable, Sendable {
    let id: String
    let name: String
    let query: String?
    let filters: AnyJSONObject
    let sort: String?
    let createdAt: String
    let updatedAt: String
}

struct SavedSearchListResponseDto: Decodable, Sendable {
    let data: [SavedSearchDto]
}

struct CreateSavedSearchRequestDto: Encodable {
    let name: String
    let query: String?
    let filters: AnyJSONObject
    let sort: String?
}

struct UpdateSavedSearchRequestDto: Encodable {
    let name: String?
    let query: String?
    let filters: AnyJSONObject?
    let sort: String?
}

// MARK: - Opaque JSON object

/// Minimal type-erased JSON object so we can decode/encode the backend's
/// `filters jsonb` column without committing to a static schema. The
/// repository layer translates this into / from `SearchFilters`.
struct AnyJSONObject: Codable, Sendable, Hashable {
    var values: [String: AnyJSONValue]

    init(_ values: [String: AnyJSONValue] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var out: [String: AnyJSONValue] = [:]
        for key in c.allKeys {
            out[key.stringValue] = try c.decode(AnyJSONValue.self, forKey: key)
        }
        self.values = out
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in values {
            try c.encode(v, forKey: AnyKey(stringValue: k)!)
        }
    }
}

indirect enum AnyJSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyJSONValue])
    case object([String: AnyJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyJSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var asString: String? { if case .string(let s) = self { return s } else { return nil } }
    var asBool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var asInt: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        default: return nil
        }
    }
    var asDouble: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    var asArray: [AnyJSONValue]? { if case .array(let v) = self { return v } else { return nil } }
    var asObject: [String: AnyJSONValue]? { if case .object(let v) = self { return v } else { return nil } }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
