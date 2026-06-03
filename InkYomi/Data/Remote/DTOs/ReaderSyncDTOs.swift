import Foundation

// Wire DTOs for the server-side reader-state sync endpoints, all mounted
// under `/api/data` (see services/app-api/src/routes/data/reader.ts).
//
// Decoder: the shared APIClient decoder uses `.convertFromSnakeCase`, so
// response DTOs are written camelCase and the snake_case columns
// (created_at, updated_at, highlighted_text, ...) decode transparently.
// Encoder: the shared encoder does NOT convert to snake_case, so request
// DTOs carry explicit snake_case CodingKeys wherever the server reads a
// snake_case field. This mirrors the rest of the codebase's convention.

// ===========================================================================
// Bookmarks  —  { id, cfi, label, created_at }   (no updated_at)
// ===========================================================================

struct BookmarkDto: Decodable, Sendable {
    let id: String
    /// Serialized Readium `Locator` JSON string. The server stores
    /// `JSON.stringify(locator.serialize())` here, byte-compatible with
    /// iOS `Locator(jsonString:)`, so no CFI translation is needed.
    let cfi: String
    let label: String?
    let createdAt: Date
}

struct BookmarkListResponseDto: Decodable, Sendable {
    let bookmarks: [BookmarkDto]
}

struct CreateBookmarkRequestDto: Encodable {
    let cfi: String
    let label: String?
}

// ===========================================================================
// Annotations (highlights + notes)
//   { id, locator (jsonb), highlighted_text, note_text, color,
//     created_at, updated_at }   color ∈ {yellow, pink, green, blue}
// ===========================================================================

struct AnnotationDto: Decodable, Sendable {
    let id: String
    /// Serialized Readium `Locator` stored as a jsonb object. Decoded as an
    /// opaque object; the coordinator re-serializes it to a Locator JSON
    /// string for the local store.
    let locator: AnyJSONObject
    let highlightedText: String
    let noteText: String?
    let color: String
    let createdAt: Date
    let updatedAt: Date
}

struct AnnotationListResponseDto: Decodable, Sendable {
    let annotations: [AnnotationDto]
}

struct CreateAnnotationRequestDto: Encodable {
    let locator: AnyJSONObject
    let highlightedText: String
    let noteText: String?
    let color: String

    enum CodingKeys: String, CodingKey {
        case locator
        case highlightedText = "highlighted_text"
        case noteText = "note_text"
        case color
    }
}

struct UpdateAnnotationRequestDto: Encodable {
    let noteText: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case noteText = "note_text"
        case color
    }
}

// ===========================================================================
// Reading progress
//   POST { cfi, percent }   /   GET { lastPosition, progressPercent }
// ===========================================================================

struct ProgressDto: Decodable, Sendable {
    /// Serialized Readium `Locator` JSON string (same encoding as bookmark cfi).
    let lastPosition: String
    let progressPercent: Double
}

struct SaveProgressRequestDto: Encodable {
    let cfi: String
    let percent: Double
}

// ===========================================================================
// Reader preferences
//   { fontSize, fontFamily, lineHeight, readingWidth, theme,
//     readingMode, columnCount }
//
// The server already returns/accepts camelCase here, so no special
// CodingKeys are needed. v1 only round-trips fontFamily / lineHeight /
// theme; the remaining fields are decoded-but-ignored and re-sent with
// safe defaults so we don't clobber the SPA's values. All response fields
// are optional to tolerate older/partial payloads and unknown shapes.
// ===========================================================================

struct ReaderPreferencesDto: Decodable, Sendable {
    let fontSize: Double?
    let fontFamily: String?
    let lineHeight: Double?
    let readingWidth: Double?
    let theme: String?
    let readingMode: String?
    let columnCount: String?
}

struct SaveReaderPreferencesRequestDto: Encodable {
    let fontSize: Double
    let fontFamily: String
    let lineHeight: Double
    let readingWidth: Double
    let theme: String
    let readingMode: String
    let columnCount: String
}

// ===========================================================================
// Color mapping  —  local hex ↔ server color name
// ===========================================================================

/// Bridges the app's hex-based highlight colors and the server's four
/// named colors (yellow, pink, green, blue). Mapping is fuzzy on the way
/// *to* the server (nearest of the four buckets) and canonical on the way
/// *back* so a round-trip is stable.
enum AnnotationColorMapping {
    static let serverColors: Set<String> = ["yellow", "pink", "green", "blue"]

    /// Canonical hex used to render each server color name locally. Chosen
    /// to match the app's existing highlight palette (HighlightEditorSheet).
    static func hex(forServerColor color: String) -> String {
        switch color {
        case "yellow": return "#F7D774"
        case "green":  return "#A8E6CF"
        case "pink":   return "#FFB7B2"
        case "blue":   return "#B5B9FF"
        default:       return "#F7D774"
        }
    }

    /// Map an arbitrary local hex color to the nearest of the four server
    /// buckets by RGB distance. Falls back to "yellow" on a malformed hex.
    static func serverColor(forHex hex: String) -> String {
        guard let rgb = rgbComponents(hex) else { return "yellow" }
        var best = "yellow"
        var bestDistance = Double.greatestFiniteMagnitude
        for name in ["yellow", "pink", "green", "blue"] {
            guard let target = rgbComponents(self.hex(forServerColor: name)) else { continue }
            let dr = rgb.r - target.r
            let dg = rgb.g - target.g
            let db = rgb.b - target.b
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = name
            }
        }
        return best
    }

    private static func rgbComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6 else { return nil }
        var int: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&int) else { return nil }
        return (
            r: Double((int >> 16) & 0xFF) / 255,
            g: Double((int >> 8) & 0xFF) / 255,
            b: Double(int & 0xFF) / 255
        )
    }
}
