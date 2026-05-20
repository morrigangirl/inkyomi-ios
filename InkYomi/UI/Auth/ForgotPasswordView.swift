import SwiftUI

/// Password reset is owned by Keycloak's hosted "reset credentials"
/// flow once we're on OAuth — there's no `POST /forgot-password`
/// endpoint anymore. This view just routes the user to the right
/// place in the system browser.
struct ForgotPasswordView: View {
    @State private var showResetPage = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Reset Password")
                .font(.inkTitle)
                .foregroundStyle(Color.inkPrimary)

            Text("We'll open the InkColors password-reset page in your browser. After you set a new password, come back to the app and tap \u{201C}Sign in with InkColors\u{201D}.")
                .font(.inkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showResetPage = true
            } label: {
                Text("Open password reset")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkPrimary)
            .padding(.horizontal, 32)

            Spacer()
        }
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showResetPage) {
            SafariView(url: Constants.Keycloak.resetPasswordURL).ignoresSafeArea()
        }
    }
}
