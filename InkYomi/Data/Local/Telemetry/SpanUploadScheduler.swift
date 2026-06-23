import Foundation
import BackgroundTasks
import UIKit

enum SpanUploadScheduler {

    /// Drain immediately when the app backgrounds, holding a `UIApplication`
    /// background-task assertion so the in-flight upload gets a few seconds to
    /// finish before the app is suspended (a bare `Task {}` in the scene-phase
    /// handler would otherwise be suspended mid-POST). This is the fast path;
    /// `scheduleUpload()` registers the deferred BGProcessingTask catch-up.
    @MainActor
    static func drainOnBackground(_ repository: SpanTelemetryRepository) {
        let app = UIApplication.shared
        let taskID = app.beginBackgroundTask(withName: "shop.inkcolors.InkYomi.spanDrain")
        guard taskID != .invalid else {
            // No background time granted — still kick the drain; the BG task
            // and next-foreground drain are the backstops.
            Task { await repository.drainAll(force: true) }
            return
        }
        Task { @MainActor in
            await repository.drainAll(force: true)
            app.endBackgroundTask(taskID)
        }
    }

    @MainActor
    static func registerTask(container: DependencyContainer) {
        let repo = container.spanTelemetryRepository
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.BackgroundTask.spanUpload,
            using: .main
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            let uploadTask = Task {
                await repo.uploadPendingBatches()
            }
            processingTask.expirationHandler = {
                uploadTask.cancel()
            }
            Task {
                _ = await uploadTask.result
                processingTask.setTaskCompleted(success: true)
                scheduleUpload()
            }
        }
    }

    static func scheduleUpload() {
        let request = BGProcessingTaskRequest(identifier: Constants.BackgroundTask.spanUpload)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
