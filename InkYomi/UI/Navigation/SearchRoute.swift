import Foundation

/// Navigation routes that point into the Phase 2 search experience.
/// Codable so they can be `Hashable` payloads on `NavigationStack`.
enum SearchRoute: Hashable, Codable {
    /// Typeahead overlay opened by tapping the Home search bar.
    case searchOverlay

    /// Full-screen results, optionally pre-filtered by query, tag, author,
    /// or series. Mirrors the Android route
    /// `search/results?q=&tagType=&tagSlug=&authorId=&seriesId=`.
    case results(
        query: String? = nil,
        tagType: TagType? = nil,
        tagSlug: String? = nil,
        authorId: String? = nil,
        seriesId: String? = nil
    )
}
