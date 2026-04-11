import Foundation

/// License Status Document checker — verifies loan status before reader open.
/// Supports offline fallback: if network unavailable and local dueAt not passed, allow read.
enum LsdStatusChecker {

    struct StatusResult {
        let status: LoanStatus
        let canRead: Bool
        let shouldRenew: Bool
    }

    static func check(loan: LoanInfo, fetchStatus: @Sendable () async throws -> LoanInfo) async -> StatusResult {
        // Try online status check
        do {
            let updated = try await fetchStatus()
            return StatusResult(
                status: updated.status,
                canRead: updated.status == .active || updated.status == .ready,
                shouldRenew: updated.isExpired && updated.canRenew
            )
        } catch {
            // Offline fallback: allow read if local dueAt hasn't passed
            if let dueAt = loan.dueAt, Date() < dueAt {
                return StatusResult(status: loan.status, canRead: true, shouldRenew: false)
            }
            return StatusResult(status: .expired, canRead: false, shouldRenew: loan.canRenew)
        }
    }
}
