import SwiftUI

struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var showPrivacyWeb = false
    @State private var showTermsWeb = false
    @State private var showDeleteConfirm = false
    @State private var showRemoveDeviceConfirm = false
    @State private var isRemoving = false
    @State private var removeError: String?

    @AppStorage(AppearancePreference.storageKey) private var appearanceRaw = AppearancePreference.system.rawValue

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(short) (\(build))"
    }

    var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    ProfileView()
                } label: {
                    settingsRow(
                        icon: "person.crop.circle",
                        title: "Profile",
                        subtitle: "Email and registered devices"
                    )
                }

                Button {
                    showRemoveDeviceConfirm = true
                } label: {
                    settingsRow(
                        icon: "iphone.slash",
                        title: "Remove this device",
                        subtitle: "Revoke this device's access and sign out"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRemoving)

                if let removeError {
                    Text(removeError)
                        .font(.caption)
                        .foregroundStyle(Color.inkError)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.label).tag(pref.rawValue)
                    }
                }
            }

            Section("Storage & data") {
                NavigationLink {
                    StorageView()
                } label: {
                    settingsRow(
                        icon: "externaldrive",
                        title: "Manage downloads",
                        subtitle: "View cache size and clear returned books"
                    )
                }
            }

            Section("Legal") {
                Button {
                    showPrivacyWeb = true
                } label: {
                    settingsRow(
                        icon: "hand.raised",
                        title: "Privacy Policy",
                        subtitle: nil
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showTermsWeb = true
                } label: {
                    settingsRow(
                        icon: "doc.text",
                        title: "Terms of Service",
                        subtitle: nil
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showDeleteConfirm = true
                } label: {
                    settingsRow(
                        icon: "trash",
                        title: "Delete my account",
                        subtitle: "Permanently remove your account and data"
                    )
                }
                .buttonStyle(.plain)
            }

            Section("Support") {
                Button {
                    MailtoComposer.open(
                        InkColorsLinks.supportEmail,
                        subject: "InkColors Reader support — \(versionString)"
                    )
                } label: {
                    settingsRow(
                        icon: "envelope",
                        title: "Contact support",
                        subtitle: InkColorsLinks.supportEmail
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AboutView()
                } label: {
                    settingsRow(
                        icon: "info.circle",
                        title: "About",
                        subtitle: versionString
                    )
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showPrivacyWeb) {
            SafariView(url: InkColorsLinks.privacyURL).ignoresSafeArea()
        }
        .sheet(isPresented: $showTermsWeb) {
            SafariView(url: InkColorsLinks.termsURL).ignoresSafeArea()
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Open email", role: .destructive) {
                MailtoComposer.open(
                    InkColorsLinks.privacyEmail,
                    subject: "Account deletion request",
                    body: deletionEmailBody
                )
            }
        } message: {
            Text("This will permanently delete your account, library, and reading history. This cannot be undone. We'll open your email app so you can send the request to our privacy team — they'll confirm and remove your account within 30 days.")
        }
        .alert("Remove this device?", isPresented: $showRemoveDeviceConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await removeThisDevice() }
            }
        } message: {
            Text("This will revoke this device's access to your library and wipe all local data (downloaded books, bookmarks, highlights). You can sign in again on this device any time.")
        }
    }

    /// Settings → "Remove this device". Two-phase:
    /// 1. Best-effort `DELETE /devices/:id` to invalidate the
    ///    Keycloak offline session server-side. Failures here are
    ///    logged but don't block the local wipe — if we're offline,
    ///    the wipe still happens and the device gets reconciled the
    ///    next time the stored refresh token tries to refresh
    ///    (`invalid_grant` → already-wiped).
    /// 2. `UserDataWipe.wipe()` — Keychain, UserDefaults, SwiftData,
    ///    downloads — followed by `authState = .unauthenticated`,
    ///    which AppRouter watches to surface the login screen.
    private func removeThisDevice() async {
        isRemoving = true
        removeError = nil
        do {
            try await container.deviceRepository.revokeCurrentDevice()
        } catch {
            // Best-effort: log and continue. The wipe still happens.
            removeError = "Server revoke failed: \(error.localizedDescription) — continuing local removal."
        }
        await UserDataWipe.wipe(container: container)
        isRemoving = false
    }

    @ViewBuilder
    private func settingsRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var deletionEmailBody: String {
        """
        Hi InkColors team,

        Please delete my account and all associated data.

        App version: \(versionString)

        Thanks.
        """
    }
}
