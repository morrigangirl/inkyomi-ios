import SwiftUI

struct LoginView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var viewModel = LoginViewModel()
    @State private var showRegister = false
    var navigateToForgotPassword: () -> Void

    var body: some View {
        let isRegular = hSizeClass == .regular
        let logoMaxWidth: CGFloat = isRegular ? 360 : 260
        let formMaxWidth: CGFloat = isRegular ? 440 : .infinity

        VStack(spacing: 32) {
            Spacer()

            // Logo
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: logoMaxWidth)
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
            .buttonStyle(InkProminentButtonStyle())
            .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
            .padding(.horizontal, 32)

            Button("Forgot Password?") {
                navigateToForgotPassword()
            }
            .foregroundStyle(Color.inkPrimaryLight)

            // Accounts are created on the web (reader-app model). Open the
            // sign-up page in an in-app Safari sheet so new users — and App
            // Review — have a clear path to an account.
            Button("New to InkColors? Create an account") {
                showRegister = true
            }
            .font(.subheadline)
            .foregroundStyle(Color.inkPrimaryLight)

            Spacer()
        }
        .frame(maxWidth: formMaxWidth)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showRegister) {
            SafariView(url: InkColorsLinks.registerURL)
                .ignoresSafeArea()
        }
    }
}
