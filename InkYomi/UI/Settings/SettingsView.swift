import SwiftUI

struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var showPrivacyWeb = false
    @State private var showTermsWeb = false
    @State private var showDeleteConfirm = false

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
                        subtitle: "Email, devices, sign out"
                    )
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
