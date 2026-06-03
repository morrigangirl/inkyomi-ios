import Foundation
import Observation

@Observable
final class AppState: @unchecked Sendable {
    var authState: AuthState = .loading

    /// Stable, client-generated device identifier. Sent as the
    /// `device_id` field on device-login and as the `X-Device-Id`
    /// header on authenticated requests; the backend stores it in
    /// `user_devices.device_identifier`.
    var deviceId: String

    /// The server-side `user_devices.id` (row primary key) that the
    /// backend assigned to *this* device on its last device-login. The
    /// device-list endpoint keys "is this the current device?" off this
    /// row id, so we persist it to recompute `isCurrent` client-side.
    /// Nil until the first successful login on this install.
    var deviceRegistrationId: String?

    init() {
        if let existing = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.deviceId) {
            self.deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: Constants.UserDefaultsKeys.deviceId)
            self.deviceId = newId
        }

        self.deviceRegistrationId = UserDefaults.standard.string(
            forKey: Constants.UserDefaultsKeys.deviceRegistrationId
        )
    }
}
