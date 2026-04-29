import Foundation

/// "More like this" entry from `GET /api/data/books/:icin/related`.
///
/// Mirrors the backend `RelatedBook` contract: a `SearchResultBook`
/// payload (so the rail can render covers, titles, authors, prices the
/// same way the search-results grid does) plus user-facing reasons for
/// surfacing this book ("Same series", "Shares: Fantasy, Romance") and
/// a numeric similarity score (mostly useful for diagnostics).
struct RelatedBook: Identifiable, Sendable, Hashable {
    let book: SearchResultBook
    let reasons: [String]
    let similarity: Double

    var id: String { book.id }
}
