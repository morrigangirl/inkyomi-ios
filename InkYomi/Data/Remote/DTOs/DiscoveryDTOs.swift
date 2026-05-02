import Foundation

/// Wire DTOs for the discovery endpoints introduced in pearlescent-dream
/// Phase 1 (commit 8bbe9e3) and the related-books endpoint used by
/// Phase 3.
///
/// The shared decoder uses `convertFromSnakeCase`, so server-side
/// `book_count` decodes into `bookCount`, `cover_montage_urls` into
/// `coverMontageUrls`, etc., without explicit `CodingKeys` on every field.
/// Snake-case-only fields (e.g. `tag_type`) still need a manual key.
///
/// Cover URLs returned by these endpoints are origin-relative
/// (`/api/covers/...`) — `BookCoverView` already prepends the
/// `https://inkcolors.shop` host before display, so the DTOs pass through
/// the raw strings unchanged.

// MARK: - Browse Hub

struct BrowseHubResponseDto: Decodable, Sendable {
    let groups: [BrowseHubGroupDto]
}

// MARK: - Combined Home (Phase 3 backend uplift)

/// Combined Home payload returned by `GET /api/data/discover/home`.
/// Composes the three independent endpoints — landing-page, browse-hub,
/// and trending — so mobile can open Home with one round trip instead
/// of three. The sub-DTOs are reused unchanged so each sub-payload maps
/// onto the same code paths the standalone fetches feed.
///
/// Not marked `Sendable` because `LandingPageResponse` doesn't currently
/// carry the conformance — it predates Swift 6's strict checking. The
/// caller (`HomeViewModel.loadLandingPage`) immediately maps to domain
/// types, so the lack of Sendable doesn't constrain real consumers.
struct DiscoverHomeResponseDto: Decodable {
    let landingPage: LandingPageResponse
    let browseHub: BrowseHubResponseDto
    let trending: TrendingResponseDto
}

struct BrowseHubGroupDto: Decodable, Sendable {
    let key: String
    let label: String
    let tiles: [BrowseHubTileDto]

    func toDomain() -> BrowseHubGroup {
        BrowseHubGroup(
            key: key,
            label: label,
            tiles: tiles.map { $0.toDomain() }
        )
    }
}

struct BrowseHubTileDto: Decodable, Sendable {
    let key: String
    let label: String
    let bookCount: Int?
    let coverMontageUrls: [String]?
    let href: String?
    let icon: String?
    let color: String?

    func toDomain() -> BrowseHubTile {
        BrowseHubTile(
            key: key,
            label: label,
            bookCount: bookCount ?? 0,
            coverMontageUrls: coverMontageUrls ?? [],
            href: href ?? "",
            icon: icon,
            color: color
        )
    }
}

// MARK: - Trending

struct TrendingResponseDto: Decodable, Sendable {
    let window: String?
    let data: [TrendingBookDto]
}

/// Subset of `SearchResultBook` we actually render in Phase 1's trending
/// row. Fields the row doesn't surface (subtitle, hook, ratingAvg,
/// ratingCount, etc.) are intentionally not decoded — adding them later
/// is a one-line change.
struct TrendingBookDto: Decodable, Sendable {
    let id: String
    let slug: String
    let icin: String?
    let title: String
    let authorName: String?
    let coverUrl: String?
    let coverCardUrl: String?
    let coverThumbUrl: String?
    let coverAlt: String?
    let priceUsd: Double?
    let isNewRelease: Bool?
    let chips: [String]?
    let trendingScore: Double?

    func toDomain() -> TrendingBook {
        TrendingBook(
            book: Book(
                id: id,
                title: title,
                slug: slug,
                icin: icin,
                coverUrl: coverCardUrl ?? coverUrl,
                authorName: authorName,
                priceUsd: priceUsd,
                hook: nil,
                chips: chips,
                isNewRelease: isNewRelease ?? false
            ),
            trendingScore: trendingScore
        )
    }
}

// MARK: - Related Books (Phase 3)

/// `GET /api/data/books/:icin/related` — Phase 3 "more like this" rail
/// on Book Detail. Returns up to 12 books ranked by tag-Jaccard
/// similarity + same-series / same-author boosts, with user-facing
/// reasons under each card.
struct RelatedBookResponseDto: Decodable, Sendable {
    let data: [RelatedBookDto]
}

struct RelatedBookDto: Decodable, Sendable {
    let book: RelatedBookCoverDto
    let reasons: [String]?
    let similarity: Double?

    func toDomain() -> RelatedBook {
        RelatedBook(
            book: book.toDomain(),
            reasons: reasons ?? [],
            similarity: similarity ?? 0
        )
    }
}

/// Subset of `SearchResultBook` the related rail actually renders. Same
/// permissive-decoding tactic as `TrendingBookDto`: fields we don't
/// surface (subtitle, hook, etc.) aren't decoded, which keeps the wire
/// surface small and tolerant of harmless server-side schema drift.
struct RelatedBookCoverDto: Decodable, Sendable {
    let id: String
    let slug: String
    let icin: String?
    let title: String
    let authorName: String?
    let coverUrl: String?
    let coverCardUrl: String?
    let coverThumbUrl: String?
    let priceUsd: Double?

    func toDomain() -> SearchResultBook {
        SearchResultBook(
            id: id,
            slug: slug,
            icin: icin,
            title: title,
            subtitle: nil,
            authorName: authorName,
            hook: nil,
            shortDescription: nil,
            coverUrl: coverUrl,
            coverThumbUrl: coverThumbUrl,
            coverCardUrl: coverCardUrl,
            coverAlt: nil,
            priceUsd: priceUsd,
            isPurchasable: true,
            isNewRelease: false,
            isFeatured: false,
            hasContentWarning: false,
            spiceLevel: nil,
            language: nil,
            ratingAvg: nil,
            ratingCount: nil,
            seriesName: nil,
            seriesNumber: nil
        )
    }
}
