import Foundation
import Observation

/// Typeahead overlay ViewModel. Debounces calls to
/// `/api/search/v2/suggest` by `debounceMs` and ignores results from
/// stale requests by cancelling the previous task on every keystroke.
@MainActor @Observable
final class SearchViewModel {
    var query: String = ""
    var isLoading: Bool = false
    var suggestions: SuggestResults?
    var errorMessage: String?

    private static let debounceMs: UInt64 = 250
    private static let minQueryLength = 2

    private var suggestTask: Task<Void, Never>?
    private var repository: (any SearchRepository)?
    private var savedSearchesRepository: (any SavedSearchesRepository)?
    /// Reference to the shared recents store, surfaced to the view.
    var recentSearches: RecentSearchesPreferences?
    /// Saved searches surfaced above the recents list in the empty
    /// state. Loaded on configure(); deleted in-place via the row's
    /// trailing action.
    private(set) var savedSearches: [SavedSearch] = []

    func configure(
        repository: any SearchRepository,
        recentSearches: RecentSearchesPreferences,
        savedSearches savedSearchesRepository: any SavedSearchesRepository
    ) {
        self.repository = repository
        self.recentSearches = recentSearches
        self.savedSearchesRepository = savedSearchesRepository
        Task { await self.refreshSavedSearches() }
    }

    func refreshSavedSearches() async {
        guard let repo = savedSearchesRepository else { return }
        if let list = try? await repo.list() {
            savedSearches = list
        }
        // Failure is silent — section just stays empty.
    }

    func deleteSavedSearch(_ id: String) async {
        guard let repo = savedSearchesRepository else { return }
        if (try? await repo.delete(id: id)) != nil {
            savedSearches.removeAll { $0.id == id }
        }
    }

    func onQueryChanged(_ newQuery: String) {
        query = newQuery
        errorMessage = nil
        suggestTask?.cancel()
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < Self.minQueryLength {
            suggestions = nil
            isLoading = false
            return
        }
        suggestTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceMs * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.fetch(query: newQuery)
        }
    }

    private func fetch(query newQuery: String) async {
        guard let repository else { return }
        isLoading = true
        do {
            let result = try await repository.suggest(query: newQuery)
            // Discard if the user has typed past this query mid-flight.
            if query == newQuery {
                suggestions = result
                isLoading = false
            }
        } catch {
            if query == newQuery {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func clearQuery() {
        suggestTask?.cancel()
        query = ""
        suggestions = nil
        isLoading = false
        errorMessage = nil
    }

    /// Called when the user actually runs a search (taps "Search for X"
    /// or hits the Search keyboard action). Bumps the query to the top
    /// of the persisted recents list.
    func rememberSubmission(_ query: String) {
        recentSearches?.add(query)
    }

    func removeRecent(_ query: String) {
        recentSearches?.remove(query)
    }

    func clearRecents() {
        recentSearches?.clear()
    }
}
