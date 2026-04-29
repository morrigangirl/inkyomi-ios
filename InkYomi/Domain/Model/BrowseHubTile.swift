import Foundation

/// One section of the Browse Hub on the Home screen — typically maps to
/// a tag-type axis (`by-genre`, `by-trope`, `by-mood`, `by-identity`,
/// `by-outcome`, `by-content`) or a curated editorial collection
/// (`by-series`, `by-character`, `featured`).
struct BrowseHubGroup: Identifiable, Sendable {
    let key: String
    let label: String
    let tiles: [BrowseHubTile]

    var id: String { key }
}

/// Single tile in a browse-hub group — typically a genre / mood / trope /
/// identity tag, or a curated editorial "browse view" backed by
/// `site_categories` on the server.
///
/// `coverMontageUrls` is a 3–5 element list of book covers to fan/overlap
/// in the tile thumbnail. `href` is the canonical web link the website
/// uses; the mobile app translates the slug + tag-type out of `key` plus
/// the parent group's `key` to build a search-results route.
struct BrowseHubTile: Identifiable, Sendable {
    let key: String
    let label: String
    let bookCount: Int
    let coverMontageUrls: [String]
    let href: String
    let icon: String?
    let color: String?

    var id: String { key }
}
