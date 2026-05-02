import Foundation

/// One row from the user's saved-searches list. Mirrors the backend
/// `SavedSearch` contract — `filters` is decoded into a typed
/// `SearchFilters` so the search UI can re-apply it directly.
///
/// `query` is nil when the saved search is filter-only; `sort` is nil
/// when the user wants the default sort behaviour for the resulting
/// search context (`.relevance` for free-text, `.newest` for
/// filter-only).
struct SavedSearch: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let query: String?
    let filters: SearchFilters
    let sort: SearchSortOrder?
    let createdAt: String
    let updatedAt: String
}
