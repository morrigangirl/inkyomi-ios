import Foundation

/// A book in the popularity-ranked feed (`/api/data/books/trending`).
/// Wraps a [Book] with the per-book trending score so the UI can show
/// a ranking badge if it ever wants to. For Phase 1 the score is
/// decoded but ignored visually.
struct TrendingBook: Identifiable, Sendable {
    let book: Book
    let trendingScore: Double?

    var id: String { book.id }
}
