import Foundation

// MARK: - Landing Page

struct LandingPageResponse: Decodable {
    let shelves: [ShelfDto]
    let heroSlides: [HeroSlideDto]
    let categories: [CategoryDto]
}

struct ShelfDto: Decodable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let sortOrder: Int?
    let books: [ShelfBookDto]

    func toDomain() -> Shelf {
        Shelf(
            id: id,
            slug: slug,
            title: title,
            books: books.map { $0.toDomain() }
        )
    }
}

struct ShelfBookDto: Decodable {
    let bookId: String
    let title: String
    let slug: String
    let icin: String?
    let coverUrl: String?
    let coverOriginalUrl: String?
    let coverCardUrl: String?
    let coverThumbUrl: String?
    let coverAlt: String?
    let authorName: String?
    let priceUsd: String?

    func toDomain() -> Book {
        Book(
            id: bookId,
            title: title,
            slug: slug,
            icin: icin,
            coverUrl: coverCardUrl ?? coverUrl,
            authorName: authorName,
            priceUsd: priceUsd.flatMap { Double($0) },
            hook: nil,
            chips: nil,
            isNewRelease: false
        )
    }
}

struct HeroSlideDto: Decodable {
    let id: String
    let eyebrow: String?
    let sortOrder: Int?
    let slideType: String
    let bannerImageUrl: String?
    let bannerAlt: String?
    let linkText: String?
    let bannerSettings: BannerSettingsDto?
    let book: HeroSlideBookDto?

    func toDomain() -> HeroSlide {
        HeroSlide(
            id: id,
            eyebrow: eyebrow,
            slideType: slideType,
            bannerImageUrl: bannerImageUrl,
            bannerSettings: bannerSettings?.toDomain(),
            book: book?.toDomain()
        )
    }
}

/// Decoder for the server's `banner_settings` JSONB payload. Server emits
/// camelCase keys inside this object (the outer envelope is snake_case);
/// `convertFromSnakeCase` passes camelCase keys through unchanged.
struct BannerSettingsDto: Decodable {
    let focalX: Double?
    let focalY: Double?
    let customZoom: Double?
    let mobileFocalX: Double?
    let mobileFocalY: Double?
    let mobileZoom: Double?
    let mobileBannerUrl: String?
    let slideClickable: Bool?

    func toDomain() -> BannerSettings {
        BannerSettings(
            focalX: focalX,
            focalY: focalY,
            customZoom: customZoom,
            mobileFocalX: mobileFocalX,
            mobileFocalY: mobileFocalY,
            mobileZoom: mobileZoom,
            mobileBannerUrl: mobileBannerUrl,
            slideClickable: slideClickable
        )
    }
}

struct HeroSlideBookDto: Decodable {
    let id: String
    let title: String
    let slug: String
    let icin: String?
    let coverUrl: String?
    let coverOriginalUrl: String?
    let coverCardUrl: String?
    let coverThumbUrl: String?
    let authorName: String?

    func toDomain() -> Book {
        Book(
            id: id,
            title: title,
            slug: slug,
            icin: icin,
            coverUrl: coverCardUrl ?? coverUrl,
            authorName: authorName,
            priceUsd: nil,
            hook: nil,
            chips: nil,
            isNewRelease: false
        )
    }
}

struct CategoryDto: Decodable {
    let id: String
    let label: String
    let slug: String

    func toDomain() -> Category {
        Category(id: id, label: label, slug: slug)
    }
}

// MARK: - Book Detail

struct BookDetailResponse: Decodable {
    let id: String
    let title: String
    let subtitle: String?
    let slug: String
    let icin: String?
    let hook: String?
    let shortDescription: String?
    let fullDescription: String?
    let authorName: String?
    let coverUrl: String?
    let coverOriginalUrl: String?
    let coverCardUrl: String?
    let coverThumbUrl: String?
    let coverAlt: String?
    let priceUsd: String?
    let isPurchasable: Bool?
    let isNewRelease: Bool?
    let ratingAvg: Double?
    let ratingCount: Int?
    let owned: Bool?
    let authors: [AuthorDto]?
    let tags: [TagDto]?
    let categories: [CategoryDto]?
    let lookInside: LookInsideDto?

    func toDomain() -> BookDetail {
        BookDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            slug: slug,
            icin: icin,
            hook: hook,
            shortDescription: shortDescription,
            fullDescription: fullDescription,
            authorName: authorName,
            coverUrl: coverCardUrl ?? coverUrl,
            priceUsd: priceUsd.flatMap { Double($0) },
            isPurchasable: isPurchasable ?? false,
            isNewRelease: isNewRelease ?? false,
            ratingAvg: ratingAvg,
            ratingCount: ratingCount,
            owned: owned ?? false,
            authors: (authors ?? []).map { $0.toDomain() },
            tags: (tags ?? []).map { $0.toDomain() },
            categories: (categories ?? []).map { $0.toDomain() },
            lookInside: lookInside?.toDomain() ?? .unavailable
        )
    }
}

/// The `look_inside` status block on the book-detail response (migration
/// 115). `available` is what the reader UI gates on — true only when the
/// feature is enabled, a successful preview exists, and the book is
/// publicly visible. The `preview_status` / `preview_failure_reason`
/// fields are author-only and ignored here.
struct LookInsideDto: Decodable {
    let enabled: Bool?
    let available: Bool?

    func toDomain() -> LookInside {
        LookInside(enabled: enabled ?? false, available: available ?? false)
    }
}

// MARK: - Look Inside preview

/// Response from `GET /api/data/books/:idOrSlug/look-inside` (no auth).
/// `previewHtml` is already sanitized server-side; the client renders it
/// in a JavaScript-disabled WKWebView, never the DRM reader.
struct LookInsidePreviewResponse: Decodable {
    let sourceTitle: String?
    let previewHtml: String
    let wordCount: Int?
    let truncated: Bool?

    func toDomain() -> LookInsidePreview {
        LookInsidePreview(
            sourceTitle: sourceTitle,
            previewHtml: previewHtml,
            wordCount: wordCount,
            truncated: truncated ?? false
        )
    }
}

struct AuthorDto: Decodable {
    let id: String
    let displayName: String
    let slug: String
    let avatarUrl: String?
    let role: String?

    func toDomain() -> Author {
        Author(id: id, name: displayName)
    }
}

struct TagDto: Decodable {
    let id: String
    let label: String
    let slug: String
    let tagType: String?

    func toDomain() -> Tag {
        Tag(
            id: id,
            label: label,
            slug: slug,
            tagType: TagType.fromWire(tagType)
        )
    }
}

// MARK: - Search
//
// The legacy v1 search DTOs (`SearchRequest`/`SearchResponse`/
// `SearchResultDto`) were removed alongside the dead `POST /api/search`
// call. All search now flows through `/api/search/v2` — see
// `SearchDTOs.swift` and `SearchAPIService`.
