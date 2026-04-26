import Foundation
import BackgroundTasks
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "LoanRenewalScheduler")

/// Periodic 24h `BGProcessingTask` that runs `LoanRenewalCoordinator` so
/// borrowed-loan renewals happen transparently even when the app is not in
/// the foreground.
///
/// Mirrors the Android `LoanRenewalWorker` (24h `PeriodicWorkRequest`).
/// The task identifier lives in `Constants.BackgroundTask.loanRenewal` and
/// must also appear under `BGTaskSchedulerPermittedIdentifiers` in
/// `Info.plist`.
enum LoanRenewalScheduler {
    @MainActor
    static func registerTask(container: DependencyContainer) {
        let coordinator = container.loanRenewalCoordinator
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.BackgroundTask.loanRenewal,
            using: .main
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            let renewTask = Task {
                await coordinator.renewExpiringSoon()
            }
            processingTask.expirationHandler = {
                renewTask.cancel()
            }
            Task {
                let summary = await renewTask.value
                logger.info("Loan renewal sweep: \(summary.renewed) renewed, \(summary.skipped) skipped, \(summary.considered) active")
                processingTask.setTaskCompleted(success: true)
                scheduleRenewal()
            }
        }
    }

    static func scheduleRenewal() {
        let request = BGProcessingTaskRequest(identifier: Constants.BackgroundTask.loanRenewal)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.warning("Failed to submit BG renewal task: \(error.localizedDescription, privacy: .public)")
        }
    }
}
