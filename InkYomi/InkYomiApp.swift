import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct InkYomiApp: App {
    @State private var container = DependencyContainer.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(container)
                .environment(container.appState)
                .modelContainer(container.modelContainer)
                .preferredColorScheme(appearance.colorScheme)
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
