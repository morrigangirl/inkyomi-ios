import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct InkYomiApp: App {
    @State private var container = DependencyContainer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(container)
                .environment(container.appState)
                .modelContainer(container.modelContainer)
                .onOpenURL { url in
                    container.deepLinkHandler.handle(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await container.spanTelemetryRepository.drainAll()
                }
                SpanUploadScheduler.scheduleUpload()
                LoanRenewalScheduler.scheduleRenewal()
            }
        }
    }

    init() {
        SpanUploadScheduler.registerTask(container: DependencyContainer.shared)
        LoanRenewalScheduler.registerTask(container: DependencyContainer.shared)
    }
}
