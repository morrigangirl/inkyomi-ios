import Foundation
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "LoanRenewal")

/// Silent loan renewal — fires whenever a logged-in user surfaces (foreground
/// trigger from `AppRouter`) and on a periodic `BGProcessingTask` job.
///
/// The goal is Kindle-style transparency: a borrower never sees an expiry
/// message until they've genuinely exhausted their renewal budget. The
/// existing on-open auto-renew in `BookRepositoryImpl.ensureLendingDownloaded`
/// is the catch-all for the moment of truth; this coordinator pre-empts it.
///
/// Strategy: walk active loans, renew anything within `proactiveWindow` of
/// its `dueAt` that still has renewals available. Failures are logged and
/// swallowed — the on-open path still gets a second chance.
actor LoanRenewalCoordinator {
    private let lendingRepository: any LendingRepository

    /// Renew anything due within 48h. Wider than 24h so a missed periodic
    /// task run (battery saver, Doze) still gets a second crack from the
    /// next foreground trigger before the on-open fallback kicks in.
    static let proactiveWindow: TimeInterval = 48 * 60 * 60

    init(lendingRepository: any LendingRepository) {
        self.lendingRepository = lendingRepository
    }

    struct Summary {
        let renewed: Int
        let skipped: Int
        let considered: Int
    }

    @discardableResult
    func renewExpiringSoon(now: Date = Date()) async -> Summary {
        do {
            try await lendingRepository.syncShelf()
        } catch {
            logger.warning("syncShelf failed before renewal sweep: \(error.localizedDescription, privacy: .public)")
        }

        let loans: [LoanInfo]
        do {
            loans = try await lendingRepository.getActiveLoans()
        } catch {
            logger.warning("getActiveLoans failed; aborting sweep: \(error.localizedDescription, privacy: .public)")
            return Summary(renewed: 0, skipped: 0, considered: 0)
        }

        var renewed = 0
        var skipped = 0
        for loan in loans {
            guard shouldRenew(loan, now: now) else {
                skipped += 1
                continue
            }
            do {
                try await lendingRepository.renewBook(loanId: loan.loanId)
                renewed += 1
                logger.info("Proactively renewed loan \(loan.loanId, privacy: .public)")
            } catch {
                // Server may reject ("not yet eligible to renew", "max
                // renewals reached", etc.). Best-effort — the on-open
                // path is the safety net.
                logger.warning("Renewal failed for loan \(loan.loanId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return Summary(renewed: renewed, skipped: skipped, considered: loans.count)
    }

    private func shouldRenew(_ loan: LoanInfo, now: Date) -> Bool {
        guard loan.status == .active else { return false }
        guard loan.canRenew else { return false }
        guard let due = loan.dueAt else { return false }
        return due.timeIntervalSince(now) <= Self.proactiveWindow
    }
}
