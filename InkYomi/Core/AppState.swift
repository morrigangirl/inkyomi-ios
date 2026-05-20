import Foundation
import Observation

@Observable
final class AppState: @unchecked Sendable {
    var authState: AuthState = .loading
    var deviceId: String
    /// Surfaced after `AuthMigrationCoordinator.bounceToOAuth()` or a
    /// terminal Keycloak refresh error so the login screen can
    /// explain "we logged you out because…" instead of showing a
    /// generic blank state. Nil during steady-state operation.
    var pendingAuthError: String?
    /// Set when the lazy-transition migration fires (a legacy
    /// session ended terminally and we want the user to know they
    /// need to sign in once more against the new OAuth flow). The
    /// login screen reads this to show "Please sign in again — we've
    /// upgraded your reader's security" instead of a generic message.
    var pendingAuthMigration: Bool = false

    init() {
        if let existing = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.deviceId) {
            self.deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: Constants.UserDefaultsKeys.deviceId)
            self.deviceId = newId
        }
    }
}
