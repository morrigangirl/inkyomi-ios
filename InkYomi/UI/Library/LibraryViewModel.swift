import Foundation
import Observation

enum LibraryTab: String, CaseIterable {
    case owned = "Owned"
    case borrowed = "Borrowed"
}

@MainActor @Observable
final class LibraryViewModel {
    var selectedTab: LibraryTab = .owned
    var ownedBooks: [LibraryBook] = []
    var borrowedBooks: [LoanInfo] = []
    var lendingEnabled = false
    var isLoading = false
    var error: String?
    var returnConfirmLoanId: String?
    var message: String?

    private var ownedLoadedAt: Date?
    private var borrowedLoadedAt: Date?
    private var libraryRepository: (any LibraryRepository)?
    private var lendingRepository: (any LendingRepository)?

    func configure(
        libraryRepository: any LibraryRepository,
        lendingRepository: any LendingRepository
    ) {
        self.libraryRepository = libraryRepository
        self.lendingRepository = lendingRepository
    }

    func initialLoad() async {
        // Check lending availability
        if let lendingRepository {
            lendingEnabled = await lendingRepository.isLendingEnabled()
        }
        await loadCurrentTab()
    }

    func loadCurrentTab() async {
        switch selectedTab {
        case .owned:
            await loadOwnedIfStale()
        case .borrowed:
            await loadBorrowedIfStale()
        }
    }

    func refresh() async {
        switch selectedTab {
        case .owned:
            await loadOwned()
        case .borrowed:
            await loadBorrowed()
        }
    }

    func onTabChanged(_ tab: LibraryTab) {
        let wasTab = selectedTab
        selectedTab = tab
        if wasTab != tab {
            Task { await loadCurrentTab() }
        }
    }

    // MARK: - Return / Renew

    func returnBook(loanId: String) {
        guard let lendingRepository else { return }
        Task {
            do {
                try await lendingRepository.returnBook(loanId: loanId)
                await loadBorrowed()
                message = "Book returned"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func renewBook(loanId: String) {
        guard let lendingRepository else { return }
        Task {
            do {
                try await lendingRepository.renewBook(loanId: loanId)
                await loadBorrowed()
                message = "Loan renewed"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func consumeMessage() {
        message = nil
    }

    // MARK: - Private

    private func loadOwnedIfStale() async {
        if let loadedAt = ownedLoadedAt,
           Date().timeIntervalSince(loadedAt) < Constants.tabStalenessThresholdSeconds {
            return
        }
        await loadOwned()
    }

    private func loadBorrowedIfStale() async {
        if let loadedAt = borrowedLoadedAt,
           Date().timeIntervalSince(loadedAt) < Constants.tabStalenessThresholdSeconds {
            return
        }
        await loadBorrowed()
    }

    private func loadOwned() async {
        guard let libraryRepository else { return }
        isLoading = ownedBooks.isEmpty
        error = nil
        do {
            ownedBooks = try await libraryRepository.getOwnedBooks()
            ownedLoadedAt = Date()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadBorrowed() async {
        guard let lendingRepository else { return }
        isLoading = borrowedBooks.isEmpty
        error = nil
        do {
            // Sync shelf first to get fresh metadata
            try? await lendingRepository.syncShelf()
            borrowedBooks = try await lendingRepository.getActiveLoans()
            borrowedLoadedAt = Date()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
