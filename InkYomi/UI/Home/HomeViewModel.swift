import Foundation
import Observation
import SwiftData

struct ContinueReadingItem: Identifiable, Sendable {
    let bookId: String
    let title: String
    let authorName: String?
    let coverUrl: String?
    let progressPercent: Float

    var id: String { bookId }
}

@MainActor @Observable
final class HomeViewModel {
    var landingPage: LandingPage?
    var isLoading = false
    var isRefreshing = false
    var error: String?
    var searchQuery = ""
    var searchResults: [Book]?
    var isSearching = false
    var continueReading: [ContinueReadingItem] = []

    private var searchTask: Task<Void, Never>?
    private var catalogRepository: (any CatalogRepository)?
    private var modelContext: ModelContext?

    func configure(catalogRepository: any CatalogRepository, modelContext: ModelContext) {
        self.catalogRepository = catalogRepository
        self.modelContext = modelContext
    }

    func loadLandingPage() async {
        guard let catalogRepository else { return }
        isLoading = true
        error = nil
        do {
            landingPage = try await catalogRepository.getLandingPage()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        loadContinueReading()
    }

    func refresh() async {
        guard let catalogRepository else { return }
        isRefreshing = true
        do {
            landingPage = try await catalogRepository.getLandingPage()
        } catch {
            self.error = error.localizedDescription
        }
        isRefreshing = false
        loadContinueReading()
    }

    func onSearchQueryChanged(_ query: String) {
        searchQuery = query
        searchTask?.cancel()

        if query.isEmpty {
            clearSearch()
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(Constants.searchDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            await searchBooks(query: query)
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchQuery = ""
        searchResults = nil
        isSearching = false
    }

    private func searchBooks(query: String) async {
        guard let catalogRepository else { return }
        isSearching = true
        do {
            searchResults = try await catalogRepository.searchBooks(query: query)
        } catch {
            if !Task.isCancelled {
                searchResults = []
            }
        }
        isSearching = false
    }

    private func loadContinueReading() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedBookModel>(
            predicate: #Predicate { $0.lastOpenedAt != nil && $0.progressPercent < 0.98 },
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        guard let books = try? modelContext.fetch(descriptor) else { return }
        continueReading = Array(books.prefix(Constants.continueReadingLimit)).map {
            ContinueReadingItem(
                bookId: $0.bookId,
                title: $0.title,
                authorName: $0.authorName,
                coverUrl: $0.coverUrl,
                progressPercent: $0.progressPercent
            )
        }
    }
}
