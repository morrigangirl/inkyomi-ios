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
    /// Server-resolved per-axis tag-filter spec (built from
    /// `site_categories.tag_filter`). Lets in-app navigation replicate
    /// the catalog's `?category=` filter without a separate API surface.
    /// Within an axis: OR; across axes: AND. Nil for tiles whose
    /// category has no `tag_filter` configured — fall through to the
    /// single-tag axis mapping or the external URL.
    let filters: [TagType: [String]]?

    var id: String { key }
}
