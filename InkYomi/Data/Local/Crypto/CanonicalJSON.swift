import Foundation

/// Canonical JSON serializer — Swift mirror of `inkyomi-crypto/canonical-json.ts`.
///
/// Rules (subset of RFC 8785):
/// - Object keys sorted lexicographically (UTF-16 code unit order).
/// - No whitespace between tokens.
/// - Strings escape per the standard JSON minimal set.
/// - "signature" field excluded by `canonicalizeForSignature`.
enum CanonicalJSON {

    static func canonicalize(_ value: Any?) -> Data {
        Data(canonicalizeToString(value).utf8)
    }

    static func canonicalizeToString(_ value: Any?) -> String {
        var result = ""
        write(&result, value)
        return result
    }

    /// Strip "signature" key and canonicalize the rest.
    static func canonicalizeForSignature(_ document: [String: Any]) -> Data {
        var copy = document
        copy.removeValue(forKey: "signature")
        return canonicalize(copy)
    }

    /// Parse JSON data, strip "signature", and canonicalize.
    static func canonicalizeForSignature(jsonData: Data) throws -> Data {
        guard let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw CanonicalJSONError.notAnObject
        }
        return canonicalizeForSignature(obj)
    }

    // MARK: - Private

    private static func write(_ result: inout String, _ value: Any?) {
        switch value {
        case nil:
            result += "null"
        case let nsnull as NSNull:
            _ = nsnull
            result += "null"
        // IMPORTANT: match NSNumber BEFORE Bool. `JSONSerialization` returns
        // every JSON number and boolean as an NSNumber, and an NSNumber that
        // wraps an integer (e.g. 1 or 0) also succeeds an `as Bool` cast —
        // so a `case let bool as Bool` placed first would mis-serialize the
        // integer 1 as `true`, corrupting the canonical bytes (and thus any
        // RSA signature computed over them). The NSNumber branch below
        // distinguishes real booleans via CFBooleanGetTypeID.
        case let number as NSNumber:
            // Check if boolean (NSNumber wraps bools too)
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                result += number.boolValue ? "true" : "false"
            } else {
                let d = number.doubleValue
                guard d.isFinite else {
                    fatalError("canonicalize: non-finite number \(number)")
                }
                // Integers as integers
                if d == Double(Int64(d)) && !d.isNaN {
                    result += String(Int64(d))
                } else {
                    result += "\(number)"
                }
            }
        case let bool as Bool:
            result += bool ? "true" : "false"
        case let string as String:
            result += jsonString(string)
        case let dict as [String: Any]:
            writeObject(&result, dict)
        case let array as [Any]:
            writeArray(&result, array)
        default:
            fatalError("canonicalize: unsupported value type \(type(of: value!))")
        }
    }

    private static func writeObject(_ result: inout String, _ obj: [String: Any]) {
        let keys = obj.keys.sorted()
        result += "{"
        var first = true
        for key in keys {
            guard let v = obj[key] else { continue }
            if !first { result += "," }
            first = false
            result += jsonString(key)
            result += ":"
            write(&result, v)
        }
        result += "}"
    }

    private static func writeArray(_ result: inout String, _ arr: [Any]) {
        result += "["
        for (i, v) in arr.enumerated() {
            if i > 0 { result += "," }
            write(&result, v)
        }
        result += "]"
    }

    /// JSON.stringify-compatible string escape.
    private static func jsonString(_ s: String) -> String {
        var sb = "\""
        for c in s {
            switch c {
            case "\"": sb += "\\\""
            case "\\": sb += "\\\\"
            case "\u{08}": sb += "\\b"
            case "\u{0C}": sb += "\\f"
            case "\n": sb += "\\n"
            case "\r": sb += "\\r"
            case "\t": sb += "\\t"
            default:
                if c.asciiValue != nil && c.asciiValue! < 0x20 {
                    sb += String(format: "\\u%04x", c.asciiValue!)
                } else if c.unicodeScalars.first!.value < 0x20 {
                    sb += String(format: "\\u%04x", c.unicodeScalars.first!.value)
                } else {
                    sb.append(c)
                }
            }
        }
        sb += "\""
        return sb
    }
}

enum CanonicalJSONError: Error {
    case notAnObject
}
