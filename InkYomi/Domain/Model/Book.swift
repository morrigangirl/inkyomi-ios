import Foundation

struct Book: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let slug: String
    /// Public-facing book identifier (US-XXXXXXXX). Used to key
    /// `/api/data/books/:icin/related` and the OPDS publication routes.
    /// Optional because some response shapes (e.g. legacy search hits)
    /// don't surface it.
    let icin: String?
    let coverUrl: String?
    let authorName: String?
    let priceUsd: Double?
    let hook: String?
    let chips: [String]?
    let isNewRelease: Bool

    init(
        id: String,
        title: String,
        slug: String,
        icin: String? = nil,
        coverUrl: String?,
        authorName: String?,
        priceUsd: Double?,
        hook: String?,
        chips: [String]?,
        isNewRelease: Bool
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.icin = icin
        self.coverUrl = coverUrl
        self.authorName = authorName
        self.priceUsd = priceUsd
        self.hook = hook
        self.chips = chips
        self.isNewRelease = isNewRelease
    }
}
