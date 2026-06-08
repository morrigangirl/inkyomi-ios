import SwiftUI

struct ForgotPasswordView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel = ForgotPasswordViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Reset Password")
                .font(.inkTitle)
                .foregroundStyle(Color.inkPrimary)

            Text("Enter your email address and we'll send you a link to reset your password.")
                .font(.inkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            TextField("Email", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 32)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(Color.inkError)
                    .font(.caption)
            }

            if viewModel.sent {
                Text("If an account exists with that email, you'll receive a reset link shortly.")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task {
                    await viewModel.submit(authRepo: container.authRepository)
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Send Reset Link")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(InkProminentButtonStyle())
            .disabled(viewModel.isLoading || viewModel.email.isEmpty)
            .padding(.horizontal, 32)

            Spacer()
        }
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: viewModel.errorMessage) { $0 }
    }
}
