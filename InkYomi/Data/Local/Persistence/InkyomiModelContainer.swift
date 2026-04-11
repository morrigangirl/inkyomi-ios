import Foundation
import SwiftData

enum InkyomiModelContainer {
    static func create() throws -> ModelContainer {
        let schema = Schema([
            CachedBookModel.self,
            LoanCacheModel.self,
            BookmarkModel.self,
            HighlightModel.self,
            ReadingSessionModel.self,
            ReadingTelemetryEventModel.self,
            InstrumentedLocationModel.self,
            PendingSpanReadModel.self,
            AccountingManifestModel.self,
        ])
        let config = ModelConfiguration(
            "InkYomi",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
