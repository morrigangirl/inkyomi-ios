import Foundation
import SwiftData

@Model
final class CachedBookModel {
    @Attribute(.unique) var bookId: String
    var title: String
    var authorName: String?
    var coverUrl: String?
    var filePath: String?
    var fileSizeBytes: Int64
    var downloadedAt: Date
    var lastOpenedAt: Date?
    var lastLocatorJson: String?
    var lastHref: String?
    var lastProgression: Double?
    var lastTotalProgression: Double?
    var lastChapterTitle: String?
    var progressPercent: Float
    var totalReadingTimeMs: Int64

    init(
        bookId: String,
        title: String,
        authorName: String? = nil,
        coverUrl: String? = nil,
        filePath: String? = nil,
        fileSizeBytes: Int64 = 0,
        downloadedAt: Date = Date(),
        progressPercent: Float = 0,
        totalReadingTimeMs: Int64 = 0
    ) {
        self.bookId = bookId
        self.title = title
        self.authorName = authorName
        self.coverUrl = coverUrl
        self.filePath = filePath
        self.fileSizeBytes = fileSizeBytes
        self.downloadedAt = downloadedAt
        self.progressPercent = progressPercent
        self.totalReadingTimeMs = totalReadingTimeMs
    }
}
