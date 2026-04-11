import Foundation

struct ReaderLocation: Equatable, Sendable {
    let bookId: String
    let locatorJson: String
    let href: String?
    let progression: Double?
    let totalProgression: Double?
    let chapterTitle: String?
}

struct ReaderBookmark: Identifiable, Equatable, Sendable {
    let id: String
    let bookId: String
    let locatorJson: String
    let chapterTitle: String?
    let label: String?
    let createdAt: Date
}

struct ReaderHighlight: Identifiable, Equatable, Sendable {
    let id: String
    let bookId: String
    let locatorJson: String
    let quote: String?
    let colorHex: String
    let style: HighlightStyle
    let note: String?
    let createdAt: Date
}

enum HighlightStyle: String, Codable, Sendable {
    case highlight
    case underline
}

enum HighlightColor: String, CaseIterable, Sendable {
    case yellow = "#FFEB3B"
    case green = "#4CAF50"
    case blue = "#2196F3"
    case pink = "#E91E63"
}

struct ReadingSession: Identifiable, Sendable {
    let id: String
    let bookId: String
    let startedAt: Date
    var endedAt: Date?
}

struct ReadingTelemetryEvent: Identifiable, Sendable {
    let id: String
    let sessionId: String
    let bookId: String
    let type: String
    let durationMs: Int64
}

struct InstrumentedLocation: Identifiable, Sendable {
    let id: String
    let bookId: String
    let label: String
    let href: String
    let progressionStart: Double
    let progressionEnd: Double
}
