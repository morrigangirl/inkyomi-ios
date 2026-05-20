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
                .onOpenURL { url in
                    // AppAuth callback: when the OAuth flow finishes
                    // Keycloak redirects to
                    // shop.inkcolors.inkyomi://auth/callback?code=…
                    // and the OS hands it back to us. Hand it to the
                    // in-flight session AppAuth is holding so the
                    // continuation in `loginWithOAuth` can resume
                    // with the issued tokens.
                    if url.scheme == "shop.inkcolors.inkyomi" {
                        KeycloakAuthRepository.resumeExternalUserAgentFlow(with: url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                Task {
                    await container.spanTelemetryRepository.drainAll()
                }
                SpanUploadScheduler.scheduleUpload()
                LoanRenewalScheduler.scheduleRenewal()
            case .active:
                // Foreground nudge: best-effort upload of any spans the
                // user wrote while offline / in airplane mode. Throttled
                // inside the repository, so this is safe to call often.
                Task {
                    await container.spanTelemetryRepository.uploadPendingBatches()
                }
            default:
                break
            }
        }
    }

    init() {
        SpanUploadScheduler.registerTask(container: DependencyContainer.shared)
        LoanRenewalScheduler.registerTask(container: DependencyContainer.shared)
    }
}
