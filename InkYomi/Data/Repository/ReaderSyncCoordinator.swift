import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "ReaderSync")

/// Offline-first coordinator for server-side reader-state sync (bookmarks,
/// annotations/highlights, reading position, reader preferences).
///
/// Design:
///   - The local SwiftData store is always the source the UI reads from.
///     Reading works fully offline; every network call here is best-effort
///     and swallows its errors (logging only) so a flaky connection never
///     blocks the reader.
///   - Writes are optimistic: the caller mutates the local store and flags
///     the row `needsSync` / `pendingDelete`; this coordinator pushes in the
///     background and records the server `id` on success. Failures leave the
///     row queued for the next push.
///
/// Conflict policy:
///   - Bookmarks have no server `updated_at`; the server enforces
///     uniqueness on `(user, book, cfi)`. We treat the server as
///     authoritative for the *set* (dedupe by cfi / locator), while never
///     dropping a local create that hasn't been pushed yet.
///   - Annotations are last-write-wins by `updated_at`.
///   - Reading position is forward-only: a pulled position is applied only
///     when it is ahead of the local one; we never move the reader backward.
///
/// MainActor-isolated to match ReaderViewModel and the SwiftData access
/// pattern used elsewhere in the app (BookRepositoryImpl talks to the
/// main context on the MainActor). SwiftData models aren't Sendable, so
/// keeping all store access on one actor avoids cross-actor model passing.
@MainActor
final class ReaderSyncCoordinator {
    private let api: ReaderSyncAPIService
    private let modelContainer: ModelContainer

    // Per-book debounce tasks for reading position.
    private var progressPushTasks: [String: Task<Void, Never>] = [:]
    // Single debounce task for reader preferences (global, not per-book).
    private var preferencesPushTask: Task<Void, Never>?

    /// Debounce window before a position change is pushed to the server.
    private let progressDebounce: Duration = .seconds(5)
    /// Debounce window before a preferences change is pushed.
    private let preferencesDebounce: Duration = .seconds(2)

    init(api: ReaderSyncAPIService, modelContainer: ModelContainer) {
        self.api = api
        self.modelContainer = modelContainer
    }

    private var context: ModelContext { modelContainer.mainContext }

    // =======================================================================
    // MARK: - Open-time sync (pull + reconcile, then flush local queue)
    // =======================================================================

    /// Called when a book is opened. Pulls server state and merges it into
    /// the local store, then pushes anything still queued locally. Entirely
    /// best-effort.
    func syncOnOpen(bookId: String) async {
        await pullBookmarks(bookId: bookId)
        await pullAnnotations(bookId: bookId)
        await pullProgress(bookId: bookId)

        await pushPendingBookmarks(bookId: bookId)
        await pushPendingAnnotations(bookId: bookId)
        await flushProgress(bookId: bookId)
    }

    /// Called when the reader closes — flush queued work immediately so the
    /// last position/edits aren't lost if the app is killed.
    func syncOnClose(bookId: String) async {
        progressPushTasks[bookId]?.cancel()
        progressPushTasks[bookId] = nil
        await pushPendingBookmarks(bookId: bookId)
        await pushPendingAnnotations(bookId: bookId)
        await flushProgress(bookId: bookId)
    }

    // =======================================================================
    // MARK: - Bookmarks — optimistic local writes + reads
    // =======================================================================

    /// Read the local bookmarks for a book (newest first), excluding rows
    /// queued for deletion. This is what the reader UI renders.
    func getBookmarks(bookId: String) -> [ReaderBookmark] {
        localBookmarks(bookId: bookId)
            .filter { !$0.pendingDelete }
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.toReaderBookmark() }
    }

    /// Optimistically add a bookmark locally (flagged needs-sync) and kick
    /// off a background push. Dedupes against an existing local bookmark at
    /// the same locator.
    @discardableResult
    func addBookmark(bookId: String, locatorJson: String, chapterTitle: String?, label: String?) -> String {
        if let existing = localBookmarks(bookId: bookId)
            .first(where: { $0.locatorJson == locatorJson && !$0.pendingDelete }) {
            return existing.id
        }
        let model = BookmarkModel(
            bookId: bookId,
            locatorJson: locatorJson,
            chapterTitle: chapterTitle,
            label: label,
            needsSync: true
        )
        context.insert(model)
        try? context.save()
        Task { await pushPendingBookmarks(bookId: bookId) }
        return model.id
    }

    /// Optimistically remove a bookmark. A never-pushed local row is dropped
    /// immediately; a server-backed row is flagged pendingDelete and the
    /// server DELETE is pushed in the background.
    func deleteBookmark(id: String) {
        let descriptor = FetchDescriptor<BookmarkModel>(predicate: #Predicate { $0.id == id })
        guard let model = try? context.fetch(descriptor).first else { return }
        let bookId = model.bookId
        if model.serverId == nil {
            context.delete(model)
            try? context.save()
            return
        }
        model.pendingDelete = true
        try? context.save()
        Task { await pushPendingBookmarks(bookId: bookId) }
    }

    // =======================================================================
    // MARK: - Bookmarks — pull / reconcile
    // =======================================================================

    private func localBookmarks(bookId: String) -> [BookmarkModel] {
        let bid = bookId
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Pull server bookmarks and reconcile. Server is authoritative for the
    /// set (dedupe by cfi == locatorJson); local un-pushed creates survive.
    private func pullBookmarks(bookId: String) async {
        let remote: [BookmarkDto]
        do {
            remote = try await api.listBookmarks(bookId: bookId)
        } catch {
            logger.debug("pullBookmarks failed: \(error.localizedDescription)")
            return
        }

        let locals = localBookmarks(bookId: bookId)
        var byServerId: [String: BookmarkModel] = [:]
        var byLocator: [String: BookmarkModel] = [:]
        for m in locals {
            if let sid = m.serverId { byServerId[sid] = m }
            byLocator[m.locatorJson] = m
        }

        let remoteServerIds = Set(remote.map { $0.id })

        // Upsert each remote bookmark into the local store.
        for dto in remote {
            if let existing = byServerId[dto.id] {
                // Already linked — refresh the label (server-authoritative).
                if existing.pendingDelete { continue }
                existing.label = dto.label
                existing.locatorJson = dto.cfi
                existing.needsSync = false
            } else if let collided = byLocator[dto.cfi], collided.serverId == nil {
                // We created this locally and the server returned the same
                // cfi — adopt the server id instead of duplicating.
                collided.serverId = dto.id
                collided.label = collided.label ?? dto.label
                collided.needsSync = false
            } else if byLocator[dto.cfi] == nil {
                let model = BookmarkModel(
                    bookId: bookId,
                    locatorJson: dto.cfi,
                    chapterTitle: nil,
                    label: dto.label,
                    createdAt: dto.createdAt,
                    serverId: dto.id,
                    needsSync: false,
                    pendingDelete: false
                )
                context.insert(model)
            }
        }

        // Drop confirmed-but-now-absent bookmarks: a row that has a serverId
        // the server no longer lists was deleted elsewhere → remove locally.
        // Never touch rows still pending a local delete or never pushed.
        for m in locals where !m.pendingDelete {
            if let sid = m.serverId, !remoteServerIds.contains(sid) {
                context.delete(m)
            }
        }

        try? context.save()
    }

    /// Push local bookmark creates / deletes that are still queued.
    func pushPendingBookmarks(bookId: String) async {
        let locals = localBookmarks(bookId: bookId)

        // Deletes first so a delete+recreate at the same cfi can't race the
        // server's (user, book, cfi) uniqueness constraint.
        for m in locals where m.pendingDelete {
            if let sid = m.serverId {
                do {
                    try await api.deleteBookmark(bookId: bookId, id: sid)
                } catch {
                    logger.debug("deleteBookmark push failed: \(error.localizedDescription)")
                    continue // keep queued
                }
            }
            context.delete(m)
        }

        for m in locals where m.needsSync && !m.pendingDelete {
            do {
                let dto = try await api.createBookmark(
                    bookId: bookId,
                    cfi: m.locatorJson,
                    label: m.label
                )
                m.serverId = dto.id
                m.needsSync = false
            } catch {
                logger.debug("createBookmark push failed: \(error.localizedDescription)")
                // keep queued for retry
            }
        }

        try? context.save()
    }

    // =======================================================================
    // MARK: - Annotations (highlights) — optimistic local writes + reads
    // =======================================================================

    /// Read the local highlights for a book (newest first), excluding rows
    /// queued for deletion.
    func getHighlights(bookId: String) -> [ReaderHighlight] {
        localHighlights(bookId: bookId)
            .filter { !$0.pendingDelete }
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.toReaderHighlight() }
    }

    /// Optimistically add a highlight locally (flagged needs-sync) and push
    /// in the background.
    @discardableResult
    func addHighlight(
        bookId: String,
        locatorJson: String,
        quote: String?,
        colorHex: String,
        style: HighlightStyle,
        note: String?
    ) -> String {
        let now = Date()
        let model = HighlightModel(
            bookId: bookId,
            locatorJson: locatorJson,
            quote: quote,
            colorHex: colorHex,
            style: style.rawValue,
            note: note,
            createdAt: now,
            updatedAt: now,
            needsSync: true
        )
        context.insert(model)
        try? context.save()
        Task { await pushPendingAnnotations(bookId: bookId) }
        return model.id
    }

    /// Optimistically edit a highlight's color / note, bumping `updatedAt`
    /// (drives last-write-wins) and re-queuing it for push.
    func updateHighlight(id: String, colorHex: String?, style: HighlightStyle?, note: String?) {
        let descriptor = FetchDescriptor<HighlightModel>(predicate: #Predicate { $0.id == id })
        guard let model = try? context.fetch(descriptor).first else { return }
        if let colorHex { model.colorHex = colorHex }
        if let style { model.style = style.rawValue }
        if let note { model.note = note }
        model.updatedAt = Date()
        model.needsSync = true
        try? context.save()
        let bookId = model.bookId
        Task { await pushPendingAnnotations(bookId: bookId) }
    }

    /// Optimistically remove a highlight. Local-only rows drop immediately;
    /// server-backed rows are flagged pendingDelete and DELETEd in the
    /// background.
    func deleteHighlight(id: String) {
        let descriptor = FetchDescriptor<HighlightModel>(predicate: #Predicate { $0.id == id })
        guard let model = try? context.fetch(descriptor).first else { return }
        let bookId = model.bookId
        if model.serverId == nil {
            context.delete(model)
            try? context.save()
            return
        }
        model.pendingDelete = true
        try? context.save()
        Task { await pushPendingAnnotations(bookId: bookId) }
    }

    // =======================================================================
    // MARK: - Annotations (highlights) — pull / reconcile
    // =======================================================================

    private func localHighlights(bookId: String) -> [HighlightModel] {
        let bid = bookId
        let descriptor = FetchDescriptor<HighlightModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Pull server annotations and reconcile with last-write-wins by
    /// `updated_at`.
    private func pullAnnotations(bookId: String) async {
        let remote: [AnnotationDto]
        do {
            remote = try await api.listAnnotations(bookId: bookId)
        } catch {
            logger.debug("pullAnnotations failed: \(error.localizedDescription)")
            return
        }

        let locals = localHighlights(bookId: bookId)
        var byServerId: [String: HighlightModel] = [:]
        for m in locals where m.serverId != nil { byServerId[m.serverId!] = m }
        let remoteServerIds = Set(remote.map { $0.id })

        for dto in remote {
            let locatorJson = locatorJsonString(from: dto.locator)
            if let existing = byServerId[dto.id] {
                if existing.pendingDelete { continue }
                // Last-write-wins: only let the server overwrite when its
                // copy is at least as new as ours. A newer local edit stays
                // and is re-queued for push.
                if dto.updatedAt >= existing.updatedAt {
                    if let locatorJson { existing.locatorJson = locatorJson }
                    existing.quote = dto.highlightedText
                    existing.note = dto.noteText
                    existing.colorHex = AnnotationColorMapping.hex(forServerColor: dto.color)
                    existing.updatedAt = dto.updatedAt
                    existing.needsSync = false
                } else {
                    existing.needsSync = true
                }
            } else {
                let model = HighlightModel(
                    bookId: bookId,
                    locatorJson: locatorJson ?? "",
                    quote: dto.highlightedText,
                    colorHex: AnnotationColorMapping.hex(forServerColor: dto.color),
                    style: HighlightStyle.highlight.rawValue,
                    note: dto.noteText,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt,
                    serverId: dto.id,
                    needsSync: false,
                    pendingDelete: false
                )
                context.insert(model)
            }
        }

        // Remove annotations deleted on the server (had a serverId, gone now).
        for m in locals where !m.pendingDelete {
            if let sid = m.serverId, !remoteServerIds.contains(sid) {
                context.delete(m)
            }
        }

        try? context.save()
    }

    /// Push local annotation creates / edits / deletes still queued.
    func pushPendingAnnotations(bookId: String) async {
        let locals = localHighlights(bookId: bookId)

        for m in locals where m.pendingDelete {
            if let sid = m.serverId {
                do {
                    try await api.deleteAnnotation(bookId: bookId, id: sid)
                } catch {
                    logger.debug("deleteAnnotation push failed: \(error.localizedDescription)")
                    continue
                }
            }
            context.delete(m)
        }

        for m in locals where m.needsSync && !m.pendingDelete {
            let serverColor = AnnotationColorMapping.serverColor(forHex: m.colorHex)
            if let sid = m.serverId {
                // Existing annotation → PATCH note + color (the only mutable
                // server fields; locator/highlighted_text are immutable).
                do {
                    let dto = try await api.updateAnnotation(
                        bookId: bookId,
                        id: sid,
                        UpdateAnnotationRequestDto(noteText: m.note, color: serverColor)
                    )
                    m.updatedAt = dto.updatedAt
                    m.needsSync = false
                } catch {
                    logger.debug("updateAnnotation push failed: \(error.localizedDescription)")
                }
            } else {
                // New annotation → POST. highlighted_text is required by the
                // server; skip rows with no quote rather than 400 forever.
                guard let quote = m.quote, !quote.isEmpty else {
                    m.needsSync = false
                    continue
                }
                guard let locatorObject = anyJSONObject(fromLocatorJson: m.locatorJson) else {
                    logger.debug("createAnnotation skipped: unparseable locator")
                    m.needsSync = false
                    continue
                }
                do {
                    let dto = try await api.createAnnotation(
                        bookId: bookId,
                        CreateAnnotationRequestDto(
                            locator: locatorObject,
                            highlightedText: quote,
                            noteText: m.note,
                            color: serverColor
                        )
                    )
                    m.serverId = dto.id
                    m.updatedAt = dto.updatedAt
                    m.needsSync = false
                } catch {
                    logger.debug("createAnnotation push failed: \(error.localizedDescription)")
                }
            }
        }

        try? context.save()
    }

    // =======================================================================
    // MARK: - Reading position (forward-only, debounced push)
    // =======================================================================

    private func cachedBook(bookId: String) -> CachedBookModel? {
        let bid = bookId
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.bookId == bid }
        )
        return try? context.fetch(descriptor).first
    }

    /// Pull server progress and apply it only if it is ahead of the local
    /// position (forward-only — never move the reader backward).
    private func pullProgress(bookId: String) async {
        let remote: ProgressDto?
        do {
            remote = try await api.getProgress(bookId: bookId)
        } catch {
            logger.debug("pullProgress failed: \(error.localizedDescription)")
            return
        }
        guard let remote else { return }
        guard let cached = cachedBook(bookId: bookId) else { return }

        // Forward-only: ignore a server position that is behind local.
        if Double(cached.progressPercent) >= remote.progressPercent { return }
        cached.lastLocatorJson = remote.lastPosition
        cached.progressPercent = Float(remote.progressPercent)
        cached.progressNeedsSync = false
        try? context.save()
    }

    /// Mark the book's position as advanced and schedule a debounced push.
    /// The caller has already persisted the new locator/percent on the
    /// CachedBookModel; this only flags it and arms the timer.
    func recordPositionChanged(bookId: String) {
        guard let cached = cachedBook(bookId: bookId) else { return }
        cached.progressNeedsSync = true
        try? context.save()
        scheduleProgressPush(bookId: bookId)
    }

    private func scheduleProgressPush(bookId: String) {
        progressPushTasks[bookId]?.cancel()
        progressPushTasks[bookId] = Task { [weak self, progressDebounce] in
            try? await Task.sleep(for: progressDebounce)
            guard !Task.isCancelled else { return }
            await self?.flushProgress(bookId: bookId)
        }
    }

    /// Push the current local position if it is flagged needing sync.
    func flushProgress(bookId: String) async {
        guard let cached = cachedBook(bookId: bookId),
              cached.progressNeedsSync,
              let locatorJson = cached.lastLocatorJson else { return }
        let percent = Double(cached.progressPercent)
        do {
            try await api.saveProgress(bookId: bookId, cfi: locatorJson, percent: percent)
            cached.progressNeedsSync = false
            try? context.save()
        } catch {
            logger.debug("saveProgress push failed: \(error.localizedDescription)")
        }
    }

    // =======================================================================
    // MARK: - Reader preferences (pull on foreground, debounced push)
    // =======================================================================

    /// Pull server preferences and apply the v1 subset (fontFamily,
    /// lineHeight, theme) onto the local UserDefaults-backed store. Unknown
    /// / device-only fields are ignored.
    func pullPreferences(into prefs: ReaderPreferences) async {
        let dto: ReaderPreferencesDto
        do {
            dto = try await api.getPreferences()
        } catch {
            logger.debug("pullPreferences failed: \(error.localizedDescription)")
            return
        }
        if let family = dto.fontFamily { prefs.fontFamily = family }
        if let lineHeight = dto.lineHeight { prefs.lineHeight = lineHeight }
        if let theme = dto.theme, let mapped = ReaderTheme(serverTheme: theme) {
            prefs.theme = mapped
        }
    }

    /// Schedule a debounced push of the v1 preference subset. The remaining
    /// server fields are sent with safe defaults so we don't clobber the
    /// SPA's values with zeros.
    func recordPreferencesChanged(_ prefs: ReaderPreferences) {
        let snapshot = SaveReaderPreferencesRequestDto(
            fontSize: 16,
            fontFamily: prefs.fontFamily,
            lineHeight: prefs.lineHeight,
            readingWidth: 720,
            theme: prefs.theme.serverTheme,
            readingMode: "paginated",
            columnCount: "2"
        )
        preferencesPushTask?.cancel()
        preferencesPushTask = Task { [weak self, preferencesDebounce] in
            try? await Task.sleep(for: preferencesDebounce)
            guard !Task.isCancelled else { return }
            do {
                try await self?.api.savePreferences(snapshot)
            } catch {
                logger.debug("savePreferences push failed: \(error.localizedDescription)")
            }
        }
    }

    // =======================================================================
    // MARK: - Locator JSON <-> opaque object helpers
    // =======================================================================

    /// Convert the server's jsonb locator object into a Locator JSON string
    /// for the local store, by encoding the opaque object back to JSON.
    private func locatorJsonString(from object: AnyJSONObject) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(object),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// Parse a Locator JSON string into the opaque object the annotation
    /// endpoint expects for its jsonb `locator` column.
    private func anyJSONObject(fromLocatorJson json: String) -> AnyJSONObject? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AnyJSONObject.self, from: data)
    }
}

// MARK: - Theme <-> server theme mapping

extension ReaderTheme {
    /// Server theme vocabulary is light | dark | sepia, which happens to
    /// match the local raw values exactly, but map explicitly so a future
    /// rename of either side is caught at the boundary.
    var serverTheme: String {
        switch self {
        case .light: return "light"
        case .dark:  return "dark"
        case .sepia: return "sepia"
        }
    }

    init?(serverTheme: String) {
        switch serverTheme {
        case "light": self = .light
        case "dark":  self = .dark
        case "sepia": self = .sepia
        default:      return nil
        }
    }
}
