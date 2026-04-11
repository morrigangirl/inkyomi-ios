import Foundation
import Observation

@MainActor @Observable
final class ForgotPasswordViewModel {
    var email = ""
    var isLoading = false
    var errorMessage: String?
    var sent = false

    func submit(authRepo: NativeAuthRepository) async {
        isLoading = true
        errorMessage = nil

        do {
            try await authRepo.forgotPassword(email: email)
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
