import Foundation
import Observation
import UIKit

@MainActor @Observable
final class LoginViewModel {
    var isLoading = false
    var errorMessage: String?

    /// Drive the AppAuth OAuth + PKCE flow. On success the Keycloak
    /// repo flips `appState.authState = .authenticated(profile)` so
    /// AppRouter swaps in the main shell automatically — there's no
    /// continuation needed here.
    func signInWithOAuth(keycloak: KeycloakAuthRepository, presenter: UIViewController) async {
        isLoading = true
        errorMessage = nil

        do {
            try await keycloak.loginWithOAuth(presenter: presenter)
        } catch is CancellationError {
            // User dismissed the system browser. No error UI needed —
            // they just bounced out of the flow. Leave the button
            // enabled for another try.
        } catch {
            // Avoid surfacing the raw AppAuth NSError chain — it's
            // typically a long "userInfo" splat. Prefer the
            // KeycloakAuthError-specific localized descriptions
            // (issuer unreachable, missing token, etc.).
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
