import Foundation
import Observation

/// Retained as a stub so any old call sites (or future plumbing for
/// a deeper hosted-flow integration) compile, but the new
/// ForgotPasswordView just routes to the Keycloak hosted reset page
/// via SafariView. No state to manage here yet.
@MainActor @Observable
final class ForgotPasswordViewModel {
    // Intentionally empty — the post-OAuth ForgotPasswordView delegates
    // to Keycloak's hosted reset flow rather than driving its own API.
}
