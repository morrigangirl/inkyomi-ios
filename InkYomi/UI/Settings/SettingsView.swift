import SwiftUI

struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if case .authenticated(let profile) = appState.authState {
                Section("Account") {
                    LabeledContent("Email", value: profile.email)
                    if let name = profile.displayName {
                        LabeledContent("Name", value: name)
                    }
                }
            }

            Section("Devices") {
                NavigationLink("Manage Devices") {
                    DeviceListView()
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await container.authRepository.signOut()
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            }
        }
        .navigationTitle("Settings")
    }
}
