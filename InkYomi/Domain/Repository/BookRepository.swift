import Foundation

enum BookSource: String, Sendable {
    case owned
    case borrowed
}

protocol BookRepository: Sendable {
    func downloadBook(bookId: String, source: BookSource) async throws -> URL
    func cacheBookMetadata(bookId: String, title: String, authorName: String?, coverUrl: String?) async
    func updateLocation(_ location: ReaderLocation) async throws
    func getLocation(bookId: String) async -> ReaderLocation?
    func addBookmark(bookId: String, locatorJson: String, chapterTitle: String?, label: String?) async throws -> String
    func deleteBookmark(id: String) async throws
    func getBookmarks(bookId: String) async throws -> [ReaderBookmark]
    func addHighlight(bookId: String, locatorJson: String, quote: String?, colorHex: String, style: HighlightStyle, note: String?) async throws -> String
    func updateHighlight(id: String, colorHex: String?, style: HighlightStyle?, note: String?) async throws
    func deleteHighlight(id: String) async throws
    func getHighlights(bookId: String) async throws -> [ReaderHighlight]
}
