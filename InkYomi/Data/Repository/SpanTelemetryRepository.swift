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
    /// loan. Each batch carries a STABLE idempotency id (assigned once and kept
    /// on the rows until a 2xx deletes them) sent as `client_batch_id`, so a
    /// resend after a lost ACK is deduped server-side and the additive dwell
    /// upsert isn't double-applied. Rows are deleted only after a 2xx, so a
    /// failure (network, 429, 401) leaves the queue intact for the next trigger.
    /// Throttled to once per `spanUploadThrottleSeconds` unless `force`;
    /// re-entrancy-guarded.
    func drainAll(force: Bool = false) async {
        if draining { return }
        if !force, let last = lastDrainAt, Date().timeIntervalSince(last) < Constants.spanUploadThrottleSeconds {
            return
        }
        draining = true
        lastDrainAt = Date()
        defer { draining = false }

        // Assign a stable batch id to any not-yet-batched rows (persisted, so a
        // retry reuses it), then snapshot into Sendable values — we never hold a
        // (non-Sendable) ModelContext across the network await.
        assignBatchIds()
        let batches = fetchPendingBatches()
        if batches.isEmpty { return }

        var budgetExhaustedLoans = Set<String>()
        for batch in batches {
            if Task.isCancelled { return }
            // Skip a loan's remaining batches once it has hit its daily budget.
            if budgetExhaustedLoans.contains(batch.loanId) { continue }

            let spans = batch.rows.map {
                SpanReadDto(accId: $0.accId, sequenceIndex: $0.sequenceIndex, enteredAt: $0.enteredAt, exitedAt: $0.exitedAt, dwellMs: $0.dwellMs)
            }
            let request = SpanUploadRequest(
                loanId: batch.loanId,
                deviceId: deviceId,
                clientTimestamp: Date(),
                clientVersion: clientVersion,
                clientBatchId: batch.batchId,
                spans: spans
            )

            do {
                let response = try await apiService.uploadSpans(request: request)
                // 2xx (incl. a server-deduped resend, or per-span rejections):
                // delete the batch — rejected/duplicate spans never succeed on
                // retry, so dropping them prevents a poison row wedging the queue.
                deleteUploaded(ids: batch.rows.map { $0.id })
                telemetryLogger.info("Uploaded \(batch.rows.count, privacy: .public) spans (accepted=\(response.accepted ?? -1, privacy: .public)) for loan \(batch.loanId, privacy: .public)")
            } catch APIError.unauthorized {
                // Session-wide auth failure — every batch would fail too; stop and
                // keep the WHOLE queue for after the next sign-in.
                telemetryLogger.notice("Telemetry unauthorized; keeping queue for next session")
                return
            } catch APIError.rateLimited {
                // Per-loan daily budget (429) — keep this batch's rows, skip the
                // rest of this loan, but keep draining OTHER loans.
                telemetryLogger.notice("Telemetry rate-limited for loan \(batch.loanId, privacy: .public); skipping its remaining batches")
                budgetExhaustedLoans.insert(batch.loanId)
                continue
            } catch let APIError.httpError(status, _) where (400 ..< 500).contains(status) {
                // Permanent client error (403 not-owned, 404 gone, 400 malformed)
                // — never succeeds on retry, so drop this batch to avoid an
                // immortal poison queue.
                telemetryLogger.error("Telemetry permanent \(status, privacy: .public) for loan \(batch.loanId, privacy: .public); dropping batch")
                deleteUploaded(ids: batch.rows.map { $0.id })
                continue
            } catch {
                // Transient (network / 5xx) — keep this batch's rows, try others.
                telemetryLogger.error("Telemetry upload failed for loan \(batch.loanId, privacy: .public); keeping queue: \(String(describing: error), privacy: .public)")
                continue
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
        let accId: String
        let sequenceIndex: Int
        let enteredAt: Date
        let exitedAt: Date?
        let dwellMs: Int64
    }

    private struct PendingBatch {
        let batchId: String
        let loanId: String
        let rows: [PendingSnapshot]
    }

    /// Assign a stable batch id to pending rows that don't have one yet, in
    /// ≤`spanBatchSize` chunks per loan, and persist it. A failed batch keeps its
    /// id, so the retry sends the same `client_batch_id` and the server dedups.
    /// Idempotent — rows already carrying a batchId are left untouched.
    private func assignBatchIds() {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingSpanReadModel>(
            predicate: #Predicate { $0.uploaded == false && $0.batchId == nil },
            sortBy: [SortDescriptor(\.enteredAt)]
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        let byLoan = Dictionary(grouping: rows, by: { $0.loanId })
        for (_, loanRows) in byLoan {
            var index = 0
            while index < loanRows.count {
                let upper = min(index + Constants.spanBatchSize, loanRows.count)
                let batchId = UUID().uuidString
                for row in loanRows[index ..< upper] { row.batchId = batchId }
                index = upper
            }
        }
        do {
            try context.save()
        } catch {
            telemetryLogger.error("assignBatchIds save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Snapshot pending rows grouped by their (already-assigned) batch id into
    /// Sendable values, so no ModelContext crosses the network await.
    private func fetchPendingBatches() -> [PendingBatch] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingSpanReadModel>(
            predicate: #Predicate { $0.uploaded == false && $0.batchId != nil },
            sortBy: [SortDescriptor(\.enteredAt)]
        )
        guard let rows = try? context.fetch(descriptor) else {
            telemetryLogger.error("drain fetch failed")
            return []
        }
        var byBatch: [String: (loanId: String, rows: [PendingSnapshot])] = [:]
        for row in rows {
            guard let batchId = row.batchId else { continue }
            let snapshot = PendingSnapshot(id: row.id, accId: row.accId, sequenceIndex: row.sequenceIndex, enteredAt: row.enteredAt, exitedAt: row.exitedAt, dwellMs: row.dwellMs)
            byBatch[batchId, default: (row.loanId, [])].rows.append(snapshot)
        }
        return byBatch.map { PendingBatch(batchId: $0.key, loanId: $0.value.loanId, rows: $0.value.rows) }
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
