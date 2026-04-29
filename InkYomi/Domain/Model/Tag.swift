import Foundation

/// Single tag returned by the catalog endpoints. Mirrors the backend
/// `BookTag` type — the `tagType` axis is what enables tag-tap navigation
/// from BookDetail into SearchResultsView via the right facet.
struct Tag: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let label: String
    let slug: String
    let tagType: TagType?
}
