import SwiftUI
import UIKit

/// OAuth-only login screen. The pre-Keycloak email/password form has
/// been retired — Keycloak hosts the credentials page, and AppAuth
/// drives `ASWebAuthenticationSession` to present it.
///
/// The screen surfaces three states:
///   • Idle — show the OAuth button.
///   • Loading — show a ProgressView while the browser is open.
///   • Error — show the localized error from the failed flow.
///
/// The "Please sign in again — we upgraded your reader's security"
/// banner is gated on `appState.pendingAuthMigration`, set by the
/// migration coordinator after a lazy-transition bounce. Cleared once
/// the user taps the OAuth button (we don't want it sticking around
/// after a successful re-sign-in).
struct LoginView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var viewModel = LoginViewModel()
    var navigateToForgotPassword: () -> Void

    var body: some View {
        let isRegular = hSizeClass == .regular
        let logoMaxWidth: CGFloat = isRegular ? 360 : 260
        let formMaxWidth: CGFloat = isRegular ? 440 : .infinity

        VStack(spacing: 32) {
            Spacer()

            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: logoMaxWidth)
                .accessibilityLabel("InkYomi")

            if appState.pendingAuthMigration {
                migrationBanner
                    .padding(.horizontal, 32)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(Color.inkError)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else if let pendingError = appState.pendingAuthError {
                Text(pendingError)
                    .foregroundStyle(Color.inkError)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await signInTapped() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign in with InkColors")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkPrimary)
            .disabled(viewModel.isLoading)
            .padding(.horizontal, 32)

            Button("Reset password") {
                navigateToForgotPassword()
            }
            .foregroundStyle(Color.inkPrimaryLight)

            Spacer()
        }
        .frame(maxWidth: formMaxWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var migrationBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign in again")
                .font(.subheadline.weight(.semibold))
            Text("We've upgraded your reader's security. Please sign in once more — you'll stay signed in until you remove this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.inkPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func signInTapped() async {
        // Clear the lazy-transition banner the moment the user
        // commits to re-signing in. The OAuth flow either succeeds
        // (banner stays cleared) or surfaces its own error, which
        // is more useful than the migration nag.
        appState.pendingAuthMigration = false
        guard let presenter = Self.topPresentingController() else {
            viewModel.errorMessage = "Couldn't open the sign-in window. Please try again."
            return
        }
        await viewModel.signInWithOAuth(
            keycloak: container.keycloakAuthRepository,
            presenter: presenter
        )
    }

    /// Reach into the active UIWindowScene to find a UIKit view
    /// controller that AppAuth can present `ASWebAuthenticationSession`
    /// on. SwiftUI doesn't surface this directly, so we traverse from
    /// the key window's rootViewController down through any presented
    /// controllers to find the topmost.
    private static func topPresentingController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? scenes.first?.windows.first
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
