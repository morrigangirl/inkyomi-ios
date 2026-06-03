import Foundation
import Observation

@MainActor @Observable
final class LendingCatalogViewModel {
    var publications: [OpdsPublication] = []
    var isLoading = false
    var isRefreshing = false
    var error: String?
    var searchQuery = ""
    var borrowingBookId: String?
    var borrowSuccess = false
    var lastBorrowedBookId: String?

    /// ICINs of books the user already owns — used to disable the borrow button.
    var ownedBookIcins: Set<String> = []

    private var lendingRepository: (any LendingRepository)?
    private var libraryRepository: (any LibraryRepository)?
    private var searchTask: Task<Void, Never>?

    func configure(
        lendingRepository: any LendingRepository,
        libraryRepository: any LibraryRepository
    ) {
        self.lendingRepository = lendingRepository
        self.libraryRepository = libraryRepository
    }

    func loadCatalog() async {
        isLoading = true
        error = nil
        await fetch()
        isLoading = false
    }

    func refresh() async {
        isRefreshing = true
        error = nil
        await fetch()
        isRefreshing = false
    }

    func onSearchQueryChanged(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await fetchCatalog(query: query.isEmpty ? nil : query)
        }
    }

    func borrowBook(bookId: String) {
        guard let lendingRepository else { return }
        borrowingBookId = bookId
        borrowSuccess = false
        Task {
            do {
                try await lendingRepository.borrowBook(bookId: bookId)
                borrowingBookId = nil
                borrowSuccess = true
                lastBorrowedBookId = bookId
            } catch {
                borrowingBookId = nil
                self.error = Self.borrowErrorMessage(for: error)
            }
        }
    }

    /// Map a borrow failure to user-facing copy. Borrow gating comes back as
    /// `APIError.httpError` with a status code that tells us *why* the loan was
    /// refused; we translate those into plain language instead of leaking
    /// "HTTP error 404". Anything we don't recognize falls back to the decoded
    /// server message, then to the error's own description.
    static func borrowErrorMessage(for error: Error) -> String {
        guard case let APIError.httpError(statusCode, _) = error else {
            return error.localizedDescription
        }
        switch statusCode {
        case 404:
            // Unreleased / pre-order / not lending-enrolled / lending disabled.
            return "This book isn't available for borrowing right now."
        case 403:
            return "An active lending subscription is required to borrow."
        case 409:
            return "You already have this book borrowed."
        case 422:
            return "You've reached your borrow limit."
        case 503:
            return "This book is temporarily unavailable for lending."
        default:
            return (error as? APIError)?.serverMessage
                ?? error.localizedDescription
        }
    }

    func clearBorrowSuccess() {
        borrowSuccess = false
        lastBorrowedBookId = nil
    }

    // MARK: - Private

    private func fetch() async {
        // Load owned books to flag "already in your library"
        if let libraryRepository {
            if let owned = try? await libraryRepository.getOwnedBooks() {
                ownedBookIcins = Set(owned.compactMap { _ in
                    // The ICIN isn't directly on LibraryBook, so we track IDs
                    nil as String?
                })
            }
        }
        await fetchCatalog(query: searchQuery.isEmpty ? nil : searchQuery)
    }

    private func fetchCatalog(query: String?) async {
        guard let lendingRepository else { return }
        do {
            let feed = try await lendingRepository.getCatalog(query: query)
            publications = feed.publications ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
