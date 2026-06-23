import Foundation
import SwiftData
import os.log

private let telemetryLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "Telemetry")

/// Span-reading telemetry for borrowed (lending) books.
///
/// Pipeline: the reader injects an IntersectionObserver (`AccSpanObserverScript`)
/// that reports per-span dwell to a `SpanObserverBridge`, which calls
/// `recordSpan(...)` here to enqueue a `PendingSpanReadModel` row. This actor
/// then drains the queue to the backend (`POST /api/telemetry/spans`) in
/// ≤`spanBatchSize` batches, deleting rows only on a confirmed 2xx so nothing is
/// double-sent or lost.
///
/// Belt-and-suspenders: draining is triggered from FIVE places (reader open,
/// a periodic timer while reading, reader close, app background with a
/// `UIApplication` task assertion, and the BGProcessingTask catch-up). Drains
/// are re-entrancy-guarded and throttled so the redundant triggers coalesce.
actor SpanTelemetryRepository {
    private let modelContainer: ModelContainer
    private let apiService: SpanTelemetryAPIService
    private let deviceId: String
    private let clientVersion: String

    /// Guards against overlapping drains (actor reentrancy across the network
    /// `await` would otherwise let two drains read the same rows and double-send).
    private var draining = false
    private var lastDrainAt: Date?

    init(modelContainer: ModelContainer, apiService: SpanTelemetryAPIService, deviceId: String) {
        self.modelContainer = modelContainer
        self.apiService = apiService
        self.deviceId = deviceId
        self.clientVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    // MARK: - Recording

    /// Enqueue one observed span dwell. Cheap; called per span exit from the
    /// reader's message-handler bridge.
    func recordSpan(
        loanId: String,
        accId: String,
        sequenceIndex: Int,
        enteredAt: Date,
        exitedAt: Date?,
        dwellMs: Int64
    ) {
        let context = ModelContext(modelContainer)
        context.insert(PendingSpanReadModel(
            loanId: loanId,
            accId: accId,
            sequenceIndex: sequenceIndex,
            enteredAt: enteredAt,
            exitedAt: exitedAt,
            dwellMs: dwellMs,
            uploaded: false
        ))
        do {
            try context.save()
        } catch {
            telemetryLogger.error("recordSpan save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Manifest cache (resilience: record spans even if a later manifest
    // fetch fails, by reusing the last good acc_id → sequence_index map).

    func cacheManifest(loanId: String, bookId: String, normalizedPageWords: Int, spans: [AccountingSpanDto]) {
        let cached = spans.map { CachedManifestSpan(accId: $0.accId, sequenceIndex: $0.sequenceIndex, wordCount: $0.wordCount) }
        let json = (try? JSONEncoder().encode(cached)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AccountingManifestModel>(predicate: #Predicate { $0.loanId == loanId })
        if let existing = try? context.fetch(descriptor).first {
            existing.bookId = bookId
            existing.normalizedPageWords = normalizedPageWords
            existing.spansJson = json
            existing.fetchedAt = Date()
        } else {
            context.insert(AccountingManifestModel(loanId: loanId, bookId: bookId, normalizedPageWords: normalizedPageWords, spansJson: json, fetchedAt: Date()))
        }
        try? context.save()
    }

    func cachedManifestMap(loanId: String) -> [String: Int]? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AccountingManifestModel>(predicate: #Predicate { $0.loanId == loanId })
        guard let row = try? context.fetch(descriptor).first,
              let data = row.spansJson.data(using: .utf8),
              let spans = try? JSONDecoder().decode([CachedManifestSpan].self, from: data) else {
            return nil
        }
        var map: [String: Int] = [:]
        for s in spans { map[s.accId] = s.sequenceIndex }
        return map.isEmpty ? nil : map
    }

    private struct CachedManifestSpan: Codable {
        let accId: String
        let sequenceIndex: Int
        let wordCount: Int
    }

    // MARK: - Draining

    /// BGProcessingTask entry point — always force-drains (the system already
    /// gated this on time + connectivity).
    func uploadPendingBatches() async {
        await drainAll(force: true)
    }

    /// Upload all pending spans, oldest first, in ≤`spanBatchSize` batches per
    /// loan. Rows are deleted only after a 2xx, so a failure (network, 429,
    /// 401) leaves the queue intact for the next trigger. Throttled to once per
    /// `spanUploadThrottleSeconds` unless `force`; re-entrancy-guarded.
    func drainAll(force: Bool = false) async {
        if draining { return }
        if !force, let last = lastDrainAt, Date().timeIntervalSince(last) < Constants.spanUploadThrottleSeconds {
            return
        }
        draining = true
        lastDrainAt = Date()
        defer { draining = false }

        // Snapshot pending rows into Sendable values so we never hold a
        // (non-Sendable) ModelContext across the network await.
        let snapshot = fetchPendingSnapshot()
        if snapshot.isEmpty { return }

        let byLoan = Dictionary(grouping: snapshot, by: { $0.loanId })
        loanLoop: for (loanId, rows) in byLoan {
            var index = 0
            while index < rows.count {
                if Task.isCancelled { return }
                let upper = min(index + Constants.spanBatchSize, rows.count)
                let chunk = Array(rows[index ..< upper])
                index = upper

                let spans = chunk.map {
                    SpanReadDto(accId: $0.accId, sequenceIndex: $0.sequenceIndex, enteredAt: $0.enteredAt, exitedAt: $0.exitedAt, dwellMs: $0.dwellMs)
                }
                let request = SpanUploadRequest(
                    loanId: loanId,
                    deviceId: deviceId,
                    clientTimestamp: Date(),
                    clientVersion: clientVersion,
                    spans: spans
                )

                do {
                    let response = try await apiService.uploadSpans(request: request)
                    // 2xx (even with per-span rejections): delete the whole chunk
                    // — rejected spans are invalid (unknown acc_id / sequence
                    // mismatch) and would never succeed on retry, so dropping
                    // them prevents a poison row from wedging the queue.
                    deleteUploaded(ids: chunk.map { $0.id })
                    telemetryLogger.info("Uploaded \(chunk.count, privacy: .public) spans (accepted=\(response.accepted ?? -1, privacy: .public)) for loan \(loanId, privacy: .public)")
                } catch APIError.unauthorized {
                    // Session-wide auth failure — every loan would fail too; stop
                    // and keep the WHOLE queue for after the next sign-in.
                    telemetryLogger.notice("Telemetry unauthorized; keeping queue for next session")
                    return
                } catch APIError.rateLimited {
                    // Per-loan daily budget (429) — keep this loan's rows but move
                    // on so other loans still drain (no cross-loan starvation).
                    telemetryLogger.notice("Telemetry rate-limited for loan \(loanId, privacy: .public); trying next loan")
                    continue loanLoop
                } catch let APIError.httpError(status, _) where (400 ..< 500).contains(status) {
                    // Permanent client error for this loan/batch (403 not-owned,
                    // 404 gone, 400 malformed) — never succeeds on retry, so drop
                    // this chunk to avoid an immortal poison queue, then move on.
                    telemetryLogger.error("Telemetry permanent \(status, privacy: .public) for loan \(loanId, privacy: .public); dropping batch")
                    deleteUploaded(ids: chunk.map { $0.id })
                    continue loanLoop
                } catch {
                    // Transient (network / 5xx) — keep this loan's rows, try others.
                    telemetryLogger.error("Telemetry upload failed for loan \(loanId, privacy: .public); keeping queue: \(String(describing: error), privacy: .public)")
                    continue loanLoop
                }
            }
        }
    }

    /// Resolve the loan id for a book for telemetry purposes. Unlike the lending
    /// repository's `getLoanForBook` (which matches only active/ready loans),
    /// this accepts any status the server credits telemetry for
    /// (active/returned/expired) so a loan that transitions to returned or
    /// expired while the reader is still open keeps recording. Returns nil for
    /// owned (non-loan) books.
    func loanIdForTelemetry(bookId: String) -> String? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<LoanCacheModel>(predicate: #Predicate { $0.bookId == bookId })
        guard let loans = try? context.fetch(descriptor) else { return nil }
        let creditable: Set<String> = ["active", "returned", "expired"]
        // Prefer an active loan if multiple cached rows exist for the book.
        return loans.first(where: { $0.status == "active" })?.loanId
            ?? loans.first(where: { creditable.contains($0.status) })?.loanId
    }

    private struct PendingSnapshot {
        let id: String
        let loanId: String
        let accId: String
        let sequenceIndex: Int
        let enteredAt: Date
        let exitedAt: Date?
        let dwellMs: Int64
    }

    private func fetchPendingSnapshot() -> [PendingSnapshot] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingSpanReadModel>(
            predicate: #Predicate { $0.uploaded == false },
            sortBy: [SortDescriptor(\.enteredAt)]
        )
        guard let rows = try? context.fetch(descriptor) else {
            telemetryLogger.error("drain fetch failed")
            return []
        }
        return rows.map {
            PendingSnapshot(id: $0.id, loanId: $0.loanId, accId: $0.accId, sequenceIndex: $0.sequenceIndex, enteredAt: $0.enteredAt, exitedAt: $0.exitedAt, dwellMs: $0.dwellMs)
        }
    }

    private func deleteUploaded(ids: [String]) {
        guard !ids.isEmpty else { return }
        let idList = ids
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingSpanReadModel>(predicate: #Predicate { idList.contains($0.id) })
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows { context.delete(row) }
        do {
            try context.save()
        } catch {
            telemetryLogger.error("delete-uploaded save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
