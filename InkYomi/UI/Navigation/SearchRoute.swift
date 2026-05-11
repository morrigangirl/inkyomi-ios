import Foundation

/// Navigation routes that point into the Phase 2 search experience.
/// Codable so they can be `Hashable` payloads on `NavigationStack`.
enum SearchRoute: Hashable, Codable {
    /// Typeahead overlay opened by tapping the Home search bar.
    case searchOverlay

    /// Full-screen results, optionally pre-filtered by query, tag, author,
    /// series, or a previously-saved search id. Mirrors the Android route
    /// `search/results?q=&tagType=&tagSlug=&authorId=&seriesId=&savedSearchId=`.
    case results(
        query: String? = nil,
        tagType: TagType? = nil,
        tagSlug: String? = nil,
        authorId: String? = nil,
        seriesId: String? = nil,
        savedSearchId: String? = nil
    )

    /// Browse Hub "Browse Views" tiles — the server resolves the
    /// category's `tag_filter` into per-axis slug buckets and we feed
    /// them straight into `SearchFilters.tagSlugs`. `label` becomes the
    /// screen title since these tiles don't carry a free-text query.
    case resultsWithFilters(filters: [TagType: [String]], label: String)
}
