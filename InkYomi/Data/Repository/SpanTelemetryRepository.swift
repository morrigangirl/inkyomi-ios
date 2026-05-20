import Foundation
import SwiftData
import os.log

private let telemetryLogger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "SpanTelemetry")

/// Span-read upload pipeline for borrowed books. iOS-side mirror of
/// Android's `SpanTelemetryRepository.uploadPendingBatches` —
/// per-loan, ≤500-rows-per-batch, fail-closed on terminal errors
/// (`403`, `404` → mark all pending as "uploaded" so we don't retry
/// forever), back off on `429`, throw on transient network failures
/// so `BGProcessingTask` will retry on its next cycle.
///
/// Lifecycle:
///   • Created once in `DependencyContainer`. Receives the spans the
///     `SpanObserverBridge` persisted into SwiftData.
///   • `drainAll()` is called on scene→background by `InkYomiApp`,
///     and on reader-close by `ReaderViewModel`.
///   • `uploadPendingBatches()` is what `SpanUploadScheduler`'s
///     `BGProcessingTask` callback invokes every ~15 min. Same body
///     as the explicit drain — single source of truth.
actor SpanTelemetryRepository {
    private let modelContainer: ModelContainer
    private let api: SpanTelemetryAPIService
    private let appState: AppState
    private let clientVersion: String

    /// Per-loan terminal-rejection cache. Once the server returns
    /// `403` or `404` for a loan we stop trying — there's no
    /// entitlement to credit reads to. Cleared on app restart, which
    /// is fine: if entitlement is restored, the new launch retries.
    private var terminalLoans: Set<String> = []
    /// Last successful upload timestamp; used by the 30-second
    /// throttle in `uploadPendingBatches()` (mirrors Android's
    /// WorkManager backoff). `drainAll()` ignores the throttle.
    private var lastUploadAt: Date?

    init(
        modelContainer: ModelContainer,
        api: SpanTelemetryAPIService,
        appState: AppState,
        clientVersion: String
    ) {
        self.modelContainer = modelContainer
        self.api = api
        self.appState = appState
        self.clientVersion = clientVersion
    }

    /// Foreground flush triggered when the scene goes to background
    /// (so the user's last reading session surfaces server-side
    /// promptly) and on reader close. Identical body to
    /// `uploadPendingBatches` but bypasses the inter-call throttle.
    func drainAll() async {
        await uploadAllPending(respectingThrottle: false)
    }

    /// Background-task / periodic upload entry point. Throttled to
    /// `Constants.spanUploadThrottleSeconds` so a rapidly-firing
    /// scheduler (e.g. simulator + manual reschedule) doesn't hammer
    /// the API.
    func uploadPendingBatches() async {
        await uploadAllPending(respectingThrottle: true)
    }

    // MARK: - Private

    private func uploadAllPending(respectingThrottle: Bool) async {
        if respectingThrottle, let last = lastUploadAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < Constants.spanUploadThrottleSeconds { return }
        }

        let loans = pendingLoanIds()
        if loans.isEmpty { return }

        let deviceId = appState.deviceId
        guard !deviceId.isEmpty else {
            telemetryLogger.warning("Skipping upload: deviceId is empty")
            return
        }

        for loanId in loans where !terminalLoans.contains(loanId) {
            do {
                try await uploadBatchesFor(loanId: loanId, deviceId: deviceId)
                lastUploadAt = Date()
            } catch SpanUploadError.rateLimited {
                telemetryLogger.info("Rate-limited for loanId=\(loanId, privacy: .public); will retry next cycle")
                // Stop iterating this cycle so we don't pile on; the
                // scheduler will fire again later.
                return
            } catch SpanUploadError.terminal(let code) {
                telemetryLogger.warning("Loan \(loanId, privacy: .public) terminal (HTTP \(code, privacy: .public)); marking all pending as uploaded")
                terminalLoans.insert(loanId)
                markAllUploadedForLoan(loanId)
            } catch {
                telemetryLogger.error("Upload failed for loanId=\(loanId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pull unsent rows for a loan in chunks of `Constants.spanBatchSize`,
    /// upload, mark uploaded. Loops until exhausted or the API rejects.
    private func uploadBatchesFor(loanId: String, deviceId: String) async throws {
        while true {
            let pending = unsentRows(loanId: loanId, limit: Constants.spanBatchSize)
            if pending.isEmpty { return }

            let spans = pending.compactMap { row -> SpanReadDto? in
                guard let exitedAt = row.exitedAt else { return nil }
                return SpanReadDto(
                    accId: row.accId,
                    sequenceIndex: row.sequenceIndex,
                    enteredAt: Self.isoFormatter.string(from: row.enteredAt),
                    exitedAt: Self.isoFormatter.string(from: exitedAt),
                    dwellMs: row.dwellMs
                )
            }

            // Rows that never received an exit timestamp (e.g. reader
            // killed mid-read before the IntersectionObserver
            // debounce fired) get marked uploaded without sending —
            // they'd be rejected at the server anyway.
            let stale = pending.filter { $0.exitedAt == nil }
            if !stale.isEmpty {
                markUploaded(ids: stale.map { $0.id })
            }
            if spans.isEmpty { continue }

            let request = SpanUploadRequest(
                loanId: loanId,
                deviceId: deviceId,
                clientTimestamp: Self.isoFormatter.string(from: Date()),
                clientVersion: clientVersion,
                spans: spans
            )

            do {
                _ = try await api.uploadSpans(request: request)
                let validIds = pending.compactMap { $0.exitedAt != nil ? $0.id : nil }
                markUploaded(ids: validIds)
                telemetryLogger.info("Uploaded \(spans.count, privacy: .public) spans for loanId=\(loanId, privacy: .public)")
            } catch let apiError as APIError {
                switch apiError {
                case .rateLimited:
                    throw SpanUploadError.rateLimited
                case .httpError(let code, _) where code == 403 || code == 404:
                    throw SpanUploadError.terminal(code)
                default:
                    throw apiError
                }
            }
        }
    }

    // MARK: - SwiftData helpers (own background context per call)

    private func pendingLoanIds() -> [String] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<PendingSpanReadModel>(
            predicate: #Predicate { !$0.uploaded }
        )
        descriptor.fetchLimit = 5000  // safety cap
        let rows = (try? context.fetch(descriptor)) ?? []
        // De-dupe loan IDs while preserving stable ordering
        var seen = Set<String>()
        var ordered: [String] = []
        for row in rows where seen.insert(row.loanId).inserted {
            ordered.append(row.loanId)
        }
        return ordered
    }

    private func unsentRows(loanId: String, limit: Int) -> [PendingSpanReadModel] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<PendingSpanReadModel>(
            predicate: #Predicate { !$0.uploaded && $0.loanId == loanId },
            sortBy: [SortDescriptor(\.enteredAt)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    private func markUploaded(ids: [String]) {
        guard !ids.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingSpanReadModel>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        if let rows = try? context.fetch(descriptor) {
            for row in rows { row.uploaded = true }
            try? context.save()
        }
    }

    private func markAllUploadedForLoan(_ loanId: String) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingSpanReadModel>(
            predicate: #Predicate { !$0.uploaded && $0.loanId == loanId }
        )
        if let rows = try? context.fetch(descriptor) {
            for row in rows { row.uploaded = true }
            try? context.save()
        }
    }

    // ISO8601DateFormatter is documented as thread-safe for `string(from:)`
    // and `date(from:)`, but Foundation hasn't annotated it `Sendable`
    // (rdar://109833627). Mark `nonisolated(unsafe)` so Swift 6 strict
    // concurrency accepts the actor-owned reuse without spawning a new
    // formatter per span batch.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private enum SpanUploadError: Error {
    case rateLimited
    case terminal(Int)
}
