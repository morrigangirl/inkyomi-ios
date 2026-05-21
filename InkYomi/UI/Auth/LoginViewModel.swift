import Foundation
import Observation

@MainActor @Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?

    func login(authRepo: NativeAuthRepository) async {
        isLoading = true
        errorMessage = nil

        do {
            try await authRepo.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
