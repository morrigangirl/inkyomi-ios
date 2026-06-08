import SwiftUI
import Observation

/// Drives the in-app account-deletion flow. App Store Review Guideline
/// 5.1.1(v) requires deletion to be *initiable in-app* — an email/"contact us"
/// flow is insufficient — so this calls the backend deletion-request endpoint
/// directly and keeps email only as a fallback.
@MainActor
@Observable
final class DeleteAccountViewModel {
    enum Phase: Equatable {
        case confirm
        case submitting
        case scheduled(graceLabel: String)
        case blocked(messages: [String])
        case failed(message: String)
    }

    private(set) var phase: Phase = .confirm
    private var service: AccountAPIService?

    func configure(service: AccountAPIService) {
        self.service = service
    }

    func submit() async {
        guard let service else { return }
        phase = .submitting
        do {
            let response = try await service.requestDeletion(reason: nil)
            phase = .scheduled(graceLabel: Self.formatGrace(response.graceEndsAt))
        } catch APIError.httpError(let statusCode, let data) {
            phase = Self.mapHTTPError(statusCode: statusCode, data: data)
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    private static func mapHTTPError(statusCode: Int, data: Data) -> Phase {
        if statusCode == 400,
           let body = try? JSONDecoder().decode(AccountDeletionBlockersError.self, from: data),
           let blockers = body.blockers, !blockers.isEmpty {
            return .blocked(messages: blockers.map(\.message))
        }
        if statusCode == 409 {
            return .failed(message: "A deletion request is already pending for this account. Check your email for the cancellation link.")
        }
        let server = APIError.httpError(statusCode: statusCode, data: data).serverMessage
        return .failed(message: server ?? "Couldn't start account deletion (error \(statusCode)). Please try again.")
    }

    private static func formatGrace(_ iso: String) -> String {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFractional.date(from: iso) ?? plain.date(from: iso) else {
            return iso
        }
        let out = DateFormatter()
        out.dateStyle = .long
        out.timeStyle = .none
        return out.string(from: date)
    }
}

struct DeleteAccountView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = DeleteAccountViewModel()

    var body: some View {
        NavigationStack {
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .navigationTitle("Delete account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .task { viewModel.configure(service: container.accountAPIService) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .confirm:
            confirmView
        case .submitting:
            VStack {
                Spacer()
                ProgressView("Requesting deletion…")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .scheduled(let graceLabel):
            scheduledView(graceLabel)
        case .blocked(let messages):
            blockedView(messages)
        case .failed(let message):
            failedView(message)
        }
    }

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "trash")
                .font(.largeTitle)
                .foregroundStyle(Color.inkError)
                .accessibilityHidden(true)
            Text("Permanently delete your account")
                .font(.title3.weight(.semibold))
            Text("This removes your account, library, and reading history. We start a 30-day grace period and email you a link to cancel if you change your mind. After the grace period this can't be undone.")
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                Task { await viewModel.submit() }
            } label: {
                Text("Delete my account").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkError)
            Button { emailFallback() } label: {
                Text("Email us instead").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func scheduledView(_ graceLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Account deletion scheduled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3.weight(.semibold))
            Text("Your account is scheduled for deletion on \(graceLabel). We've emailed you a confirmation with a link to cancel before then.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task {
                    await container.authRepository.signOut()
                    dismiss()
                }
            } label: {
                Text("Sign out").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func blockedView(_ messages: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Can't delete yet", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3.weight(.semibold))
            Text("Please resolve the following before deleting your account:")
                .foregroundStyle(.secondary)
            ForEach(messages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }
            Spacer()
            Button { emailFallback() } label: {
                Text("Email our team").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Something went wrong", systemImage: "xmark.octagon.fill")
                .foregroundStyle(Color.inkError)
                .font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await viewModel.submit() } } label: {
                Text("Try again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button { emailFallback() } label: {
                Text("Email us instead").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func emailFallback() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        MailtoComposer.open(
            InkColorsLinks.privacyEmail,
            subject: "Account deletion request",
            body: """
            Hi InkColors team,

            Please delete my account and all associated data.

            App version: v\(short) (\(build))

            Thanks.
            """
        )
    }
}
