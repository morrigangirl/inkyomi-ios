import Foundation
import BackgroundTasks

enum SpanUploadScheduler {
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
