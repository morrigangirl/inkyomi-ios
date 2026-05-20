import Foundation
import SwiftData

enum InkyomiModelContainer {
    /// Every user-scoped @Model type the app persists. Exposed so
    /// `UserDataWipe` can iterate and delete every row on device
    /// removal — keep this list in sync when new persistent models
    /// are added or the wipe will silently leak data across users.
    static let modelTypes: [any PersistentModel.Type] = [
        CachedBookModel.self,
        LoanCacheModel.self,
        BookmarkModel.self,
        HighlightModel.self,
        ReadingSessionModel.self,
        ReadingTelemetryEventModel.self,
        InstrumentedLocationModel.self,
        PendingSpanReadModel.self,
        AccountingManifestModel.self,
    ]

    static func create() throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let config = ModelConfiguration(
            "InkYomi",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
