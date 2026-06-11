import Foundation
import Observation
import SwiftData
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumStreamer
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "Reader")

/// Data needed to open the EPUB navigator.
struct ReaderDocument {
    let fileURL: URL
    let publication: Publication
    let initialLocator: Locator?
}

/// Pending highlight waiting for user confirmation.
struct PendingHighlight {
    var locatorJson: String
    let quote: String?
    var colorHex: String = "#F7D774"
    var note: String = ""
}

/// Table-of-contents item.
struct TocItem: Identifiable {
    let id = UUID()
    let title: String
    let href: String
    let depth: Int
    let children: [TocItem]
}

@MainActor @Observable
final class ReaderViewModel {
    // MARK: - Published State
    var isLoading = true
    var isDownloading = false
    var error: String?
    var bookTitle = ""
    var document: ReaderDocument?

    var currentLocatorJson: String?
    var progressPercent: Float = 0

    var showControls = true
    var bookmarks: [ReaderBookmark] = []
    var highlights: [ReaderHighlight] = []
    var tocItems: [TocItem] = []

    var pendingHighlight: PendingHighlight?
    var isNotesSheetVisible = false
    var isTocVisible = false
    var isSettingsVisible = false

    var isSearchVisible = false
    var searchQuery = ""
    var isSearching = false
    var message: String?

    // Read-aloud (TTS). Set by the host VC's ReaderTTSController.
    var isReadAloudAvailable = false
    var isReadAloudPlaying = false

    // MARK: - Reader Preferences
    var fontScale: Double = 1.0
    var lineHeight: Double = 1.4
    var pageMargins: Double = 1.0
    var fontFamily: String = "serif"
    var theme: ReaderTheme = .light
    var pageLayout: ReaderPageLayout = .auto

    // MARK: - Private
    let bookId: String
    private var modelContext: ModelContext?
    private var bookRepository: (any BookRepository)?
    private var lendingRepository: (any LendingRepository)?
    private var readerPreferences: ReaderPreferences?
    private var contentProtection: InkyomiContentProtection?
    private var readerSyncCoordinator: ReaderSyncCoordinator?

    // Session tracking
    private var activeHref: String?
    private var activeLocationStart: Date?

    // Readium objects (kept for lifetime)
    private var assetRetriever: AssetRetriever?
    private var publicationOpener: PublicationOpener?

    init(bookId: String) {
        self.bookId = bookId
    }

    func configure(
        bookRepository: any BookRepository,
        lendingRepository: any LendingRepository,
        modelContext: ModelContext,
        readerPreferences: ReaderPreferences,
        contentProtection: InkyomiContentProtection,
        readerSyncCoordinator: ReaderSyncCoordinator
    ) {
        self.bookRepository = bookRepository
        self.lendingRepository = lendingRepository
        self.modelContext = modelContext
        self.readerPreferences = readerPreferences
        self.contentProtection = contentProtection
        self.readerSyncCoordinator = readerSyncCoordinator
        loadSettings()
    }

    // MARK: - Load Book

    private func debugLog(_ msg: String) {
        // Debug-only diagnostics. Gated out of Release so we never do
        // synchronous file I/O on the reader-open path and never write
        // reading activity to Documents (which is included in backups).
        #if DEBUG
        let logFile = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reader_debug.log")
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logFile)
            }
        }
        #endif
    }

    func loadBook() async {
        guard let bookRepository else {
            debugLog("loadBook: bookRepository is nil")
            return
        }
        isLoading = true
        isDownloading = true
        error = nil

        // Load cached metadata
        if let cached = fetchCachedBook() {
            bookTitle = cached.title
        }

        do {
            // Determine if this is a borrowed or owned book
            let source: BookSource
            if let lendingRepository,
               let _ = try? await lendingRepository.getLoanForBook(bookId: bookId) {
                source = .borrowed
                debugLog("[Reader] loadBook: detected BORROWED book \(self.bookId)")
            } else {
                source = .owned
                debugLog("[Reader] loadBook: detected OWNED book \(self.bookId)")
            }

            // Download/locate the EPUB file
            debugLog("[Reader] loadBook: downloading bookId=\(self.bookId) source=\(source.rawValue)")
            let fileURL = try await bookRepository.downloadBook(bookId: bookId, source: source)
            debugLog("[Reader] loadBook: got file at \(fileURL.path)")
            isDownloading = false

            // Pull + reconcile server reader-state into the local store
            // BEFORE we read the resume position, so a forward-only server
            // position (read on another device) is honored on open. Fully
            // best-effort — reading works offline if this no-ops.
            await readerSyncCoordinator?.syncOnOpen(bookId: bookId)

            // Refresh cached info
            let refreshed = fetchCachedBook()
            let initialLocatorJson = refreshed?.lastLocatorJson
            if let t = refreshed?.title, !t.isEmpty { bookTitle = t }

            // Update last opened
            if let cached = refreshed {
                cached.lastOpenedAt = Date()
                try? modelContext?.save()
            }

            // Open the publication with Readium
            let pub = try await openPublication(at: fileURL)

            // Build initial locator from stored JSON
            var initialLocator: Locator?
            if let json = initialLocatorJson {
                initialLocator = try? Locator(jsonString: json)
            }

            // Extract TOC
            tocItems = pub.manifest.tableOfContents.map { link in
                tocItemFromLink(link, depth: 0)
            }

            document = ReaderDocument(
                fileURL: fileURL,
                publication: pub,
                initialLocator: initialLocator
            )
            progressPercent = refreshed?.progressPercent ?? 0
            isLoading = false

            // Load annotations (reads the local store the sync merged into)
            loadBookmarks()
            loadHighlights()

        } catch {
            debugLog("[Reader] FAILED to load book \(self.bookId): \(error)")
            self.error = error.localizedDescription
            isLoading = false
            isDownloading = false
        }
    }

    @MainActor
    private func openPublication(at fileURL: URL) async throws -> Publication {
        guard let absoluteURL = FileURL(url: fileURL) else {
            throw NSError(domain: "ReaderError", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Invalid file URL"
            ])
        }

        let httpClient = DefaultHTTPClient()
        let retriever = AssetRetriever(httpClient: httpClient)
        self.assetRetriever = retriever

        let protections: [ContentProtection] = contentProtection.map { [$0] } ?? []

        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: retriever,
                pdfFactory: DefaultPDFDocumentFactory()
            ),
            contentProtections: protections
        )
        self.publicationOpener = opener

        let asset = try await retriever.retrieve(url: absoluteURL).get()
        debugLog("[Reader] openPublication: asset format=\(asset.format) type=\(type(of: asset))")
        let openResult = await opener.open(asset: asset, allowUserInteraction: false)
        let publication: Publication
        switch openResult {
        case .success(let pub):
            publication = pub
        case .failure(let error):
            debugLog("[Reader] openPublication FAILED: \(error)")
            throw error
        }

        debugLog("[Reader] publication readingOrder count=\(publication.readingOrder.count), metadata.title=\(publication.metadata.title ?? "nil"), resources=\(publication.manifest.resources.count)")
        if publication.readingOrder.isEmpty {
            debugLog("[Reader] readingOrder is EMPTY — this likely means the EPUB parser failed to read the OPF")
        } else {
            debugLog("[Reader] first readingOrder href=\(publication.readingOrder.first?.href ?? "nil")")
        }

        guard !publication.readingOrder.isEmpty else {
            throw NSError(domain: "ReaderError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Publication has empty reading order"
            ])
        }

        return publication
    }

    // MARK: - Location Tracking

    func handleLocatorChanged(_ locator: Locator) {
        // Serialize locator to JSON string using Readium's json property
        let jsonDict = locator.json
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict),
              let json = String(data: jsonData, encoding: .utf8) else { return }

        let href = locator.href.string
        let totalProgression = locator.locations.totalProgression ?? locator.locations.progression ?? 0

        // Close previous location
        closeActiveLocation()

        activeHref = href
        activeLocationStart = Date()
        currentLocatorJson = json

        progressPercent = min(max(Float(totalProgression), 0), 1)

        // Save reading position
        Task {
            await saveReadingPosition(locatorJson: json, progression: totalProgression)
        }
    }

    private func closeActiveLocation() {
        guard let _ = activeHref, let start = activeLocationStart else { return }
        let durationMs = Int64(Date().timeIntervalSince(start) * 1000)
        if durationMs > 0, let cached = fetchCachedBook() {
            cached.totalReadingTimeMs += durationMs
            try? modelContext?.save()
        }
        activeHref = nil
        activeLocationStart = nil
    }

    private func saveReadingPosition(locatorJson: String, progression: Double) async {
        guard let cached = fetchCachedBook() else { return }
        cached.lastLocatorJson = locatorJson
        cached.progressPercent = Float(progression)
        try? modelContext?.save()
        // Flag for a debounced (~5s) push to /progress. Forward-only is
        // enforced on the pull side; locally we always store the latest.
        readerSyncCoordinator?.recordPositionChanged(bookId: bookId)
    }

    // MARK: - Controls

    func toggleControls() {
        showControls.toggle()
    }

    // MARK: - Read-aloud (TTS)
    // These post to the host VC, which owns the ReaderTTSController (it has
    // the publication + navigator needed to speak and follow the page).

    func toggleReadAloud() {
        NotificationCenter.default.post(name: .readerReadAloudToggle, object: nil)
    }

    func readAloudNext() {
        NotificationCenter.default.post(name: .readerReadAloudNext, object: nil)
    }

    func readAloudPrevious() {
        NotificationCenter.default.post(name: .readerReadAloudPrevious, object: nil)
    }

    // MARK: - TOC

    private func tocItemFromLink(_ link: Link, depth: Int) -> TocItem {
        TocItem(
            title: link.title ?? link.href,
            href: link.href,
            depth: depth,
            children: link.children.map { tocItemFromLink($0, depth: depth + 1) }
        )
    }

    // MARK: - Bookmarks

    func addBookmark(locator: Locator) {
        guard let readerSyncCoordinator else { return }
        let jsonDict = locator.json
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict),
              let json = String(data: jsonData, encoding: .utf8) else { return }

        // Optimistic local write + background push handled by the coordinator.
        readerSyncCoordinator.addBookmark(
            bookId: bookId,
            locatorJson: json,
            chapterTitle: locator.title,
            label: locator.title ?? "Bookmark"
        )
        loadBookmarks()
        message = "Bookmark added"
    }

    func deleteBookmark(id: String) {
        readerSyncCoordinator?.deleteBookmark(id: id)
        loadBookmarks()
    }

    private func loadBookmarks() {
        bookmarks = readerSyncCoordinator?.getBookmarks(bookId: bookId) ?? []
    }

    // MARK: - Highlights

    func prepareHighlight(locator: Locator, quote: String?) {
        let jsonDict = locator.json
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        pendingHighlight = PendingHighlight(locatorJson: json, quote: quote)
    }

    func confirmHighlight() {
        guard let pending = pendingHighlight, let readerSyncCoordinator else { return }
        pendingHighlight = nil
        // Optimistic local write + background push handled by the coordinator.
        readerSyncCoordinator.addHighlight(
            bookId: bookId,
            locatorJson: pending.locatorJson,
            quote: pending.quote,
            colorHex: pending.colorHex,
            style: .highlight,
            note: pending.note.isEmpty ? nil : pending.note
        )
        loadHighlights()
    }

    func cancelPendingHighlight() {
        pendingHighlight = nil
    }

    /// Edit an existing highlight's color and/or note. Optimistic; the
    /// coordinator bumps `updatedAt` (last-write-wins) and pushes a PATCH.
    func editHighlight(id: String, colorHex: String?, note: String?) {
        readerSyncCoordinator?.updateHighlight(id: id, colorHex: colorHex, style: nil, note: note)
        loadHighlights()
    }

    func deleteHighlight(id: String) {
        readerSyncCoordinator?.deleteHighlight(id: id)
        loadHighlights()
    }

    private func loadHighlights() {
        highlights = readerSyncCoordinator?.getHighlights(bookId: bookId) ?? []
    }

    // MARK: - Settings

    private func loadSettings() {
        guard let prefs = readerPreferences else { return }
        fontScale = prefs.fontSize
        lineHeight = prefs.lineHeight
        pageMargins = prefs.pageMargins
        fontFamily = prefs.fontFamily
        theme = prefs.theme
        pageLayout = prefs.pageLayout
    }

    func updateFontScale(_ scale: Double) {
        fontScale = min(max(scale, 0.8), 1.8)
        saveSettings()
    }

    func updateLineHeight(_ height: Double) {
        lineHeight = min(max(height, 1.0), 2.5)
        saveSettings()
    }

    func updatePageMargins(_ margins: Double) {
        pageMargins = min(max(margins, 0.5), 2.0)
        saveSettings()
    }

    func updateFontFamily(_ family: String) {
        fontFamily = family
        saveSettings()
    }

    func updateTheme(_ newTheme: ReaderTheme) {
        theme = newTheme
        saveSettings()
    }

    func updatePageLayout(_ newLayout: ReaderPageLayout) {
        pageLayout = newLayout
        saveSettings()
        // Readium's `applyPreferences()` only invalidates pagination on a few
        // settings (spread, scroll, fit, ...). columnCount changes only update
        // CSS, which WebKit doesn't reliably reflow. Force a full navigator
        // reload to actually repaginate.
        NotificationCenter.default.post(name: .readerPageLayoutChanged, object: nil)
    }

    private func saveSettings() {
        guard let prefs = readerPreferences else { return }
        prefs.fontSize = fontScale
        prefs.lineHeight = lineHeight
        prefs.pageMargins = pageMargins
        prefs.fontFamily = fontFamily
        prefs.theme = theme
        prefs.pageLayout = pageLayout
        NotificationCenter.default.post(name: .readerPreferencesChanged, object: nil)
        // Debounced push of the synced subset (fontFamily, lineHeight, theme).
        readerSyncCoordinator?.recordPreferencesChanged(prefs)
    }

    // MARK: - Search

    func showSearch(_ visible: Bool) {
        isSearchVisible = visible
        if !visible {
            searchQuery = ""
            isSearching = false
        }
    }

    // MARK: - Lifecycle

    func onBackgrounded() {
        closeActiveLocation()
    }

    func onForegrounded() {
        activeLocationStart = Date()
        // Pull reader preferences on foreground and reflect any remote
        // change into the live reader settings.
        guard let coordinator = readerSyncCoordinator, let prefs = readerPreferences else { return }
        Task {
            await coordinator.pullPreferences(into: prefs)
            loadSettings()
            NotificationCenter.default.post(name: .readerPreferencesChanged, object: nil)
        }
    }

    func closeReader() {
        closeActiveLocation()
        // Flush queued position + bookmark/annotation pushes immediately so
        // nothing is lost if the app is killed after close.
        guard let coordinator = readerSyncCoordinator else { return }
        let bid = bookId
        Task { await coordinator.syncOnClose(bookId: bid) }
    }

    // MARK: - SwiftData Helpers

    private func fetchCachedBook() -> CachedBookModel? {
        guard let modelContext else { return nil }
        let bid = bookId
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func consumeMessage() {
        message = nil
    }
}
