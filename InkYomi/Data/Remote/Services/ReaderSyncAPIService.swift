import Foundation

/// Backend reader-state sync (bookmarks, annotations, progress, reader
/// preferences). All endpoints sit under `/api/data` and require the bearer
/// token (`authenticate` middleware server-side); the APIClient injects the
/// auth header. See services/app-api/src/routes/data/reader.ts.
struct ReaderSyncAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Bookmarks

    func listBookmarks(bookId: String) async throws -> [BookmarkDto] {
        let response: BookmarkListResponseDto = try await client.request(
            Endpoint(path: "data/books/\(bookId)/bookmarks")
        )
        return response.bookmarks
    }

    func createBookmark(bookId: String, cfi: String, label: String?) async throws -> BookmarkDto {
        try await client.request(Endpoint(
            path: "data/books/\(bookId)/bookmarks",
            method: .post,
            body: CreateBookmarkRequestDto(cfi: cfi, label: label)
        ))
    }

    func deleteBookmark(bookId: String, id: String) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/books/\(bookId)/bookmarks/\(id)",
            method: .delete
        ))
    }

    // MARK: - Annotations

    func listAnnotations(bookId: String) async throws -> [AnnotationDto] {
        let response: AnnotationListResponseDto = try await client.request(
            Endpoint(path: "data/books/\(bookId)/annotations")
        )
        return response.annotations
    }

    func createAnnotation(bookId: String, _ request: CreateAnnotationRequestDto) async throws -> AnnotationDto {
        try await client.request(Endpoint(
            path: "data/books/\(bookId)/annotations",
            method: .post,
            body: request
        ))
    }

    func updateAnnotation(bookId: String, id: String, _ request: UpdateAnnotationRequestDto) async throws -> AnnotationDto {
        try await client.request(Endpoint(
            path: "data/books/\(bookId)/annotations/\(id)",
            method: .patch,
            body: request
        ))
    }

    func deleteAnnotation(bookId: String, id: String) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/books/\(bookId)/annotations/\(id)",
            method: .delete
        ))
    }

    // MARK: - Reading progress

    /// Returns nil when the server has no stored progress for this book
    /// (the endpoint responds with a JSON `null` body in that case).
    func getProgress(bookId: String) async throws -> ProgressDto? {
        try await client.request(Endpoint(path: "data/books/\(bookId)/progress"))
    }

    func saveProgress(bookId: String, cfi: String, percent: Double) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/books/\(bookId)/progress",
            method: .post,
            body: SaveProgressRequestDto(cfi: cfi, percent: percent)
        ))
    }

    // MARK: - Reader preferences

    func getPreferences() async throws -> ReaderPreferencesDto {
        try await client.request(Endpoint(path: "data/reader-preferences"))
    }

    func savePreferences(_ request: SaveReaderPreferencesRequestDto) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/reader-preferences",
            method: .post,
            body: request
        ))
    }
}
