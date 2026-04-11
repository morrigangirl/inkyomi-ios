import SwiftUI

struct LoginView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel = LoginViewModel()
    var navigateToForgotPassword: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260)
                .accessibilityLabel("InkYomi")

            // Form fields
            VStack(spacing: 16) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 32)

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(Color.inkError)
                    .font(.caption)
            }

            // Login button
            Button {
                Task {
                    await viewModel.login(authRepo: container.authRepository)
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkPrimary)
            .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
            .padding(.horizontal, 32)

            Button("Forgot Password?") {
                navigateToForgotPassword()
            }
            .foregroundStyle(Color.inkPrimaryLight)

            Spacer()
        }
    }
}
