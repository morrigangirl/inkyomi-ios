import Foundation

struct AccountRepositoryImpl: AccountRepository, Sendable {
    private let api: AccountAPIService

    init(api: AccountAPIService) {
        self.api = api
    }

    func requestAccountDeletion(reason: String?) async throws -> AccountDeletionOutcome {
        do {
            let response = try await api.requestDeletion(reason: reason)
            return AccountDeletionOutcome(
                graceEndsAt: response.graceEndsAt,
                booksWithdrawn: response.booksWithdrawn
            )
        } catch APIError.httpError(let statusCode, let data) {
            throw Self.mapError(statusCode: statusCode, data: data)
        }
    }

    /// Translate the server's `400`/`409` bodies into a domain error.
    private static func mapError(statusCode: Int, data: Data) -> Error {
        if statusCode == 400,
           let body = try? JSONDecoder().decode(AccountDeletionBlockersErrorDto.self, from: data),
           body.error == "blockers_present" {
            let hard = body.blockers.filter { $0.kind == "hard" }
            // Defensive: if the server flagged blockers but none parsed as
            // "hard", still surface them so the user isn't left on a silent
            // failure with no explanation.
            let source = hard.isEmpty ? body.blockers : hard
            return AccountDeletionError.blocked(
                source.map { AccountDeletionBlocker(code: $0.code, message: $0.message) }
            )
        }

        if statusCode == 409 {
            return AccountDeletionError.alreadyPending
        }

        return AccountDeletionError.server(
            "Couldn't delete your account. Please try again."
        )
    }
}
