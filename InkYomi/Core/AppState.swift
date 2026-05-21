import Foundation
import Observation

@Observable
final class AppState: @unchecked Sendable {
    var authState: AuthState = .loading
    var deviceId: String

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
