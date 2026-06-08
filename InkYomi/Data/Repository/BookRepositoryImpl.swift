import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "BookRepo")

/// Book repository handling downloads (owned + borrowed), reading position,
/// bookmarks, and highlights.
actor BookRepositoryImpl: BookRepository {
    private let modelContainer: ModelContainer
    private let apiClient: APIClient
    private let entitlementAPI: EntitlementAPIService
    private let readerAPI: ReaderAPIService
    private let lendingAPI: OpdsLendingAPIService
    private let lendingDownloadManager: LendingDownloadManager
    private let transportSecretStore: LcpTransportSecretStore

    init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        entitlementAPI: EntitlementAPIService,
        lendingAPI: OpdsLendingAPIService,
        lendingDownloadManager: LendingDownloadManager,
        transportSecretStore: LcpTransportSecretStore
    ) {
        self.modelContainer = modelContainer
        self.apiClient = apiClient
        self.entitlementAPI = entitlementAPI
        self.readerAPI = ReaderAPIService(client: apiClient)
        self.lendingAPI = lendingAPI
        self.lendingDownloadManager = lendingDownloadManager
        self.transportSecretStore = transportSecretStore
    }

    // MARK: - Download

    @MainActor
    func downloadBook(bookId: String, source: BookSource) async throws -> URL {
        switch source {
        case .owned:
            return try await ensureOwnedDownloaded(bookId: bookId)
        case .borrowed:
            return try await ensureLendingDownloaded(bookId: bookId)
        }
    }

    // MARK: - Owned download

    // Not @MainActor: the network download + disk I/O run off the main
    // actor so a large EPUB never blocks UI. Only the SwiftData
    // `mainContext` reads/writes hop onto the main actor (mainContext is
    // main-actor bound), mirroring the streaming lending fix.
    private func ensureOwnedDownloaded(bookId: String) async throws -> URL {
        let bid = bookId

        // Check for already-cached file (SwiftData touch on the main actor).
        if let cachedPath = await MainActor.run(body: { () -> String? in
            let context = modelContainer.mainContext
            let descriptor = FetchDescriptor<CachedBookModel>(
                predicate: #Predicate { $0.bookId == bid }
            )
            return (try? context.fetch(descriptor).first)?.filePath
        }), FileManager.default.fileExists(atPath: cachedPath) {
            return URL(fileURLWithPath: cachedPath)
        }

        // Step 1: Get signed download URL
        let artifact = try await readerAPI.getDownloadUrl(bookId: bookId)
        guard let downloadURL = URL(string: artifact.downloadUrl) else {
            throw NSError(domain: "BookRepository", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Invalid download URL returned by server"
            ])
        }

        // Save to Documents/books/
        let booksDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("books", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
        let fileURL = booksDir.appendingPathComponent("\(bookId).epub")

        // Step 2: Stream the EPUB straight to disk instead of buffering the
        // whole file (up to the backend cap) in memory — matches the lending
        // download path. The temp file URLSession hands back is moved into
        // place with FileManager.moveItem. Error behavior is unchanged from
        // the old `data(from:)`: transport failures still throw here, and we
        // intentionally don't add an HTTP-status guard (the old code didn't
        // have one) so the success/throw contract is identical.
        let (downloadedURL, _) = try await URLSession.shared.download(from: downloadURL)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: fileURL)

        // Exclude from iCloud backup
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = fileURL
        try mutableURL.setResourceValues(resourceValues)

        // Create or update CachedBookModel (SwiftData touch on the main actor).
        try await MainActor.run {
            let context = modelContainer.mainContext
            let descriptor = FetchDescriptor<CachedBookModel>(
                predicate: #Predicate { $0.bookId == bid }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.filePath = fileURL.path
            } else {
                let cached = CachedBookModel(bookId: bookId, title: "", authorName: nil, coverUrl: nil)
                cached.filePath = fileURL.path
                context.insert(cached)
            }
            try context.save()
        }

        return fileURL
    }

    // MARK: - Lending download

    @MainActor
    private func ensureLendingDownloaded(bookId: String) async throws -> URL {
        let context = modelContainer.mainContext
        let bid = bookId

        // Find the active loan for this book
        let loanDescriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.bookId == bid && ($0.status == "active" || $0.status == "ready") }
        )
        guard let loan = try? context.fetch(loanDescriptor).first else {
            throw NSError(domain: "BookRepository", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "No active loan found for this book"
            ])
        }
        let loanId = loan.loanId

        // 1. Check loan status (LSD check)
        let loanInfo = loan.toLoanInfo()
        let fetchStatus: @Sendable () async throws -> LoanInfo = { [lendingAPI] in
            let status = try await lendingAPI.getLoanStatus(loanId: loanId)
            return LoanInfo(
                loanId: loanId,
                licenseId: status.id,
                bookId: bookId,
                status: LoanStatus(rawValue: status.status) ?? .active,
                dueAt: loanInfo.dueAt,
                renewedCount: loanInfo.renewedCount,
                maxRenewals: loanInfo.maxRenewals
            )
        }
        let statusResult = await LsdStatusChecker.check(loan: loanInfo, fetchStatus: fetchStatus)

        if !statusResult.canRead {
            if statusResult.shouldRenew {
                // Try auto-renew
                logger.info("Attempting auto-renew for loanId=\(loanId)")
                do {
                    _ = try await lendingAPI.renewBook(loanId: loanId)
                    loan.status = "active"
                    loan.renewedCount += 1
                    try? context.save()
                } catch {
                    throw NSError(domain: "BookRepository", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Loan expired and renewal failed: \(error.localizedDescription)"
                    ])
                }
            } else {
                throw NSError(domain: "BookRepository", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Loan \(statusResult.status.rawValue): this book is no longer available"
                ])
            }
        }

        // 2. Ensure transport secret is available locally
        // If borrowed on another device, it won't be in local Keychain yet.
        if transportSecretStore.getTransportSecretHex(loanId) == nil {
            logger.info("Transport secret missing locally for loanId=\(loanId); fetching from server")
            do {
                let secretResponse = try await lendingAPI.getTransportSecret(loanId: loanId)
                try transportSecretStore.storeTransportSecretHex(secretResponse.transportSecretHex, loanId: loanId)
            } catch {
                throw NSError(domain: "BookRepository", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Could not retrieve decryption key for this loan: \(error)"
                ])
            }
        }

        // 3. Check for existing downloaded file
        let existingFile = lendingDownloadManager.getLendingBookFile(loanId: loanId)
        if FileManager.default.fileExists(atPath: existingFile.path) {
            logger.info("Lending EPUB already cached for loanId=\(loanId)")
            return existingFile
        }

        // 4. Fetch the license (raw bytes to preserve server's signature)
        logger.info("Downloading lending EPUB for loanId=\(loanId) bookId=\(bookId)")
        let licenseData = try await lendingAPI.getLicenseRaw(loanId: loanId)

        // 5. Parse just enough to extract the publication download link
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let license = try decoder.decode(LcpLicenseDocument.self, from: licenseData)
        guard let contentLink = license.links.first(where: { $0.rel == "publication" }) else {
            throw LendingDownloadError.noPublicationLink
        }

        // 6. Download EPUB and inject raw license bytes (not re-encoded DTO)
        let tokenProvider = await apiClient.tokenProvider
        let file = try await lendingDownloadManager.downloadAndInjectLicense(
            downloadUrl: contentLink.href,
            loanId: loanId,
            licenseData: licenseData,
            tokenProvider: tokenProvider
        )

        // 7. Update CachedBookModel with file path
        let bookDescriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        if let cached = try? context.fetch(bookDescriptor).first {
            cached.filePath = file.path
        } else {
            let cached = CachedBookModel(
                bookId: bookId,
                title: loan.bookTitle ?? "",
                authorName: loan.authorName,
                coverUrl: loan.coverUrl
            )
            cached.filePath = file.path
            context.insert(cached)
        }
        try context.save()

        return file
    }

    // MARK: - Metadata Cache

    @MainActor
    func cacheBookMetadata(bookId: String, title: String, authorName: String?, coverUrl: String?) async {
        let context = modelContainer.mainContext
        let bid = bookId
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        if let cached = try? context.fetch(descriptor).first {
            if cached.title.isEmpty { cached.title = title }
            if cached.authorName == nil { cached.authorName = authorName }
            if cached.coverUrl == nil { cached.coverUrl = coverUrl }
        } else {
            let cached = CachedBookModel(
                bookId: bookId,
                title: title,
                authorName: authorName,
                coverUrl: coverUrl
            )
            context.insert(cached)
        }
        try? context.save()
    }

    // MARK: - Reading Position

    @MainActor
    func updateLocation(_ location: ReaderLocation) async throws {
        let context = modelContainer.mainContext
        let bid = location.bookId
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        guard let cached = try? context.fetch(descriptor).first else { return }
        cached.lastLocatorJson = location.locatorJson
        cached.progressPercent = Float(location.totalProgression ?? location.progression ?? 0)
        try context.save()
    }

    @MainActor
    func getLocation(bookId: String) async -> ReaderLocation? {
        let context = modelContainer.mainContext
        let bid = bookId
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        guard let cached = try? context.fetch(descriptor).first,
              let json = cached.lastLocatorJson else { return nil }
        return ReaderLocation(
            bookId: bookId,
            locatorJson: json,
            href: nil,
            progression: Double(cached.progressPercent),
            totalProgression: Double(cached.progressPercent),
            chapterTitle: nil
        )
    }

    // MARK: - Bookmarks

    @MainActor
    func addBookmark(bookId: String, locatorJson: String, chapterTitle: String?, label: String?) async throws -> String {
        let context = modelContainer.mainContext
        let bookmark = BookmarkModel(bookId: bookId, locatorJson: locatorJson)
        bookmark.chapterTitle = chapterTitle
        bookmark.label = label
        context.insert(bookmark)
        try context.save()
        return bookmark.id
    }

    @MainActor
    func deleteBookmark(id: String) async throws {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.id == id }
        )
        if let bookmark = try? context.fetch(descriptor).first {
            context.delete(bookmark)
            try context.save()
        }
    }

    @MainActor
    func getBookmarks(bookId: String) async throws -> [ReaderBookmark] {
        let context = modelContainer.mainContext
        let bid = bookId
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.bookId == bid },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map {
            ReaderBookmark(
                id: $0.id,
                bookId: $0.bookId,
                locatorJson: $0.locatorJson,
                chapterTitle: $0.chapterTitle,
                label: $0.label,
                createdAt: $0.createdAt
            )
        }
    }

    // MARK: - Highlights

    @MainActor
    func addHighlight(bookId: String, locatorJson: String, quote: String?, colorHex: String, style: HighlightStyle, note: String?) async throws -> String {
        let context = modelContainer.mainContext
        let highlight = HighlightModel(bookId: bookId, locatorJson: locatorJson, colorHex: colorHex)
        highlight.quote = quote
        highlight.style = style.rawValue
        highlight.note = note
        context.insert(highlight)
        try context.save()
        return highlight.id
    }

    @MainActor
    func updateHighlight(id: String, colorHex: String?, style: HighlightStyle?, note: String?) async throws {
        let context = modelContainer.mainContext
        let hid = id
        let descriptor = FetchDescriptor<HighlightModel>(
            predicate: #Predicate { $0.id == hid }
        )
        if let highlight = try? context.fetch(descriptor).first {
            if let c = colorHex { highlight.colorHex = c }
            if let s = style { highlight.style = s.rawValue }
            if let n = note { highlight.note = n }
            try context.save()
        }
    }

    @MainActor
    func deleteHighlight(id: String) async throws {
        let context = modelContainer.mainContext
        let hid = id
        let descriptor = FetchDescriptor<HighlightModel>(
            predicate: #Predicate { $0.id == hid }
        )
        if let highlight = try? context.fetch(descriptor).first {
            context.delete(highlight)
            try context.save()
        }
    }

    @MainActor
    func getHighlights(bookId: String) async throws -> [ReaderHighlight] {
        let context = modelContainer.mainContext
        let bid = bookId
        let descriptor = FetchDescriptor<HighlightModel>(
            predicate: #Predicate { $0.bookId == bid },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map {
            ReaderHighlight(
                id: $0.id,
                bookId: $0.bookId,
                locatorJson: $0.locatorJson,
                quote: $0.quote,
                colorHex: $0.colorHex,
                style: HighlightStyle(rawValue: $0.style) ?? .highlight,
                note: $0.note,
                createdAt: $0.createdAt
            )
        }
    }
}
