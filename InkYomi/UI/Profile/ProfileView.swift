import SwiftUI

/// Read-only account / profile screen. Surfaces the cached `UserProfile`
/// (email + display name from the auth response, no PATCH yet), the count
/// of registered devices with a chevron through to the existing manager,
/// and the canonical Sign Out button (relocated from the Settings root
/// during the v1 settings revamp).
struct ProfileView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var viewModel = ProfileViewModel()

    private var profile: UserProfile? {
        if case .authenticated(let user) = appState.authState {
            return user
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                profileHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
            }

            Section {
                NavigationLink {
                    DeviceListView()
                } label: {
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text("Registered devices")
                            Text(deviceLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Sign out has moved to Settings → "Remove this device".
            // It's the canonical "I'm done with this device" surface
            // because it also revokes the Keycloak session server-side
            // and runs UserDataWipe — a local-only signOut would leak
            // your library to the next user of this physical device.
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(deviceRepository: container.deviceRepository)
            await viewModel.loadDeviceCount()
        }
    }

    private var deviceLabel: String {
        if viewModel.isLoadingDevices { return "Loading…" }
        switch viewModel.deviceCount {
        case .some(1): return "1 device"
        case .some(let count): return "\(count) devices"
        case .none: return "Manage your registered devices"
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        HStack(spacing: 16) {
            avatarBubble
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayName?.isEmpty == false ? profile!.displayName! : "Reader")
                    .font(.title2.weight(.semibold))
                if let email = profile?.email, !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var avatarBubble: some View {
        ZStack {
            Circle()
                .fill(Color.inkPrimary.opacity(0.18))
            Text(initials())
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.inkPrimary)
        }
        .frame(width: 64, height: 64)
    }

    private func initials() -> String {
        let source = profile?.displayName?.isEmpty == false ? profile!.displayName! : (profile?.email ?? "")
        let parts = source
            .split(whereSeparator: { " @.".contains($0) })
            .filter { !$0.isEmpty }
        switch parts.count {
        case 0: return "?"
        case 1: return String(parts[0].prefix(2)).uppercased()
        default: return "\(parts[0].first ?? "?")\(parts[1].first ?? "?")".uppercased()
        }
    }
}
