import Foundation
import Observation

@MainActor @Observable
final class DeleteAccountViewModel {
    enum Phase {
        case idle
        case submitting
        /// Hard blockers returned by the server; the user must resolve them.
        case blocked([AccountDeletionBlocker])
        /// Request accepted — grace period started, awaiting sign-out.
        case requested
    }

    private(set) var phase: Phase = .idle
    var error: String?

    private var account: (any AccountRepository)?
    private var auth: (any AuthRepository)?

    var isSubmitting: Bool {
        if case .submitting = phase { return true }
        return false
    }

    var blockers: [AccountDeletionBlocker] {
        if case .blocked(let blockers) = phase { return blockers }
        return []
    }

    func configure(account: any AccountRepository, auth: any AuthRepository) {
        self.account = account
        self.auth = auth
    }

    func requestDeletion() async {
        guard let account else { return }
        phase = .submitting
        error = nil
        do {
            _ = try await account.requestAccountDeletion(reason: nil)
            phase = .requested
        } catch AccountDeletionError.blocked(let blockers) {
            phase = .blocked(blockers)
        } catch AccountDeletionError.alreadyPending {
            // Already scheduled — treat as success so the user can sign out.
            phase = .requested
        } catch {
            phase = .idle
            self.error = error.localizedDescription
        }
    }

    /// Finish the flow after the confirmation screen: clear the local
    /// session. `signOut()` flips `appState.authState` to `.unauthenticated`,
    /// so `AppRouter` swaps the whole shell for the login screen.
    func signOut() async {
        await auth?.signOut()
    }
}
