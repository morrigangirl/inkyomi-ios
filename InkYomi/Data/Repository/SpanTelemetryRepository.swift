import Foundation
import SwiftData

/// Span telemetry collection and upload for borrowed books.
/// Full implementation in Phase 8 — this is the interface stub.
actor SpanTelemetryRepository {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func drainAll() async {
        // Phase 8: Flush all pending span observations
    }

    func uploadPendingBatches() async {
        // Phase 8: Upload batches of ≤500 spans, 30s throttle, 429 retry
    }
}
