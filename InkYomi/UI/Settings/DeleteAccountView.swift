import SwiftUI

/// In-app account deletion (App Store Guideline 5.1.1(v)). Initiates the
/// server's 30-day grace deletion via `AccountRepository`, surfaces any
/// blockers, and on success signs the user out.
struct DeleteAccountView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel = DeleteAccountViewModel()
    @State private var showConfirm = false

    var body: some View {
        Group {
            switch viewModel.phase {
            case .requested:
                requestedView
            default:
                formView
            }
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(
                account: container.accountRepository,
                auth: container.authRepository
            )
        }
    }

    // MARK: - Pre-request form

    private var formView: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("This can't be undone after 30 days", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("Deleting your account starts a 30-day grace period. During that window you can cancel by signing back in. After 30 days, your account, library, and reading history are permanently erased.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !viewModel.blockers.isEmpty {
                Section("Resolve these first") {
                    ForEach(viewModel.blockers) { blocker in
                        Label(blocker.message, systemImage: "xmark.octagon")
                            .font(.subheadline)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Delete my account")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSubmitting)
            }
        }
        .confirmationDialog("Delete your account?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete my account", role: .destructive) {
                Task { await viewModel.requestDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This starts a 30-day countdown to permanent deletion. You can cancel by signing back in before it ends.")
        }
        .alert("Couldn't delete account", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Post-request confirmation

    private var requestedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 56))
                .foregroundStyle(Color.inkPrimary)
            Text("Account scheduled for deletion")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Your account will be permanently deleted in 30 days. To cancel, just sign back in before then. We'll sign you out now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.signOut() }
            } label: {
                Text("Sign out")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkPrimary)
        }
        .padding(32)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )
    }
}
