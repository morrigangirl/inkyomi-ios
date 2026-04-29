import Foundation

/// Wire DTOs for `/api/search/v2` and `/api/search/v2/suggest`.
/// Decoder uses `convertFromSnakeCase` strategy globally; only fields
/// with non-snake-case wire names need explicit `CodingKeys`.
///
/// Cover URLs come back origin-relative (`/api/covers/...`) — `BookCoverView`
/// already prepends the host before display, so the DTOs pass through
/// raw strings unchanged.

// MARK: - Search

/// Wraps a string field that the backend sometimes serializes as a
/// number. The contract type is `string`, but historic seed data and
/// some response paths emit raw integers (e.g. `"seriesNumber":3`).
/// kotlinx-serialization on Android coerces type mismatches silently;
/// Swift's `JSONDecoder` does not, so this wrapper does it explicitly.
struct StringOrNumber: Decodable, Sendable {
    let value: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int.self) { value = String(i); return }
        if let d = try? c.decode(Double.self) {
            // Don't render trailing `.0` for integer-valued doubles.
            if d.rounded() == d, abs(d) < Double(Int.max) {
                value = String(Int(d))
            } else {
                value = String(d)
            }
            return
        }
        value = nil
    }
}

struct SearchResultBookDto: Decodable, Sendable {
    let id: String
    let slug: String
    let icin: String?
    let title: String
    let subtitle: String?
    let authorName: String?
    let hook: String?
    let shortDescription: String?
    let coverUrl: String?
    let coverThumbUrl: String?
    let coverCardUrl: String?
    let coverAlt: String?
    let priceUsd: Double?
    let isPurchasable: Bool?
    let isNewRelease: Bool?
    let isFeatured: Bool?
    let hasContentWarning: Bool?
    let spiceLevel: Int?
    let language: String?
    let ratingAvg: Double?
    let ratingCount: Int?
    let seriesName: String?
    let seriesNumber: StringOrNumber?

    func toDomain() -> SearchResultBook {
        SearchResultBook(
            id: id,
            slug: slug,
            icin: icin,
            title: title,
            subtitle: subtitle,
            authorName: authorName,
            hook: hook,
            shortDescription: shortDescription,
            coverUrl: coverUrl,
            coverThumbUrl: coverThumbUrl,
            coverCardUrl: coverCardUrl,
            coverAlt: coverAlt,
            priceUsd: priceUsd,
            isPurchasable: isPurchasable ?? true,
            isNewRelease: isNewRelease ?? false,
            isFeatured: isFeatured ?? false,
            hasContentWarning: hasContentWarning ?? false,
            spiceLevel: spiceLevel,
            language: language,
            ratingAvg: ratingAvg,
            ratingCount: ratingCount,
            seriesName: seriesName,
            seriesNumber: seriesNumber?.value
        )
    }
}

struct FacetItemDto: Decodable, Sendable {
    let value: String
    let label: String
    let count: Int
    let color: String?
    let icon: String?

    func toDomain() -> FacetItem {
        FacetItem(value: value, label: label, count: count, color: color, icon: icon)
    }
}

struct FacetGroupDto: Decodable, Sendable {
    let key: String
    let label: String
    let items: [FacetItemDto]?

    func toDomain() -> FacetGroup {
        FacetGroup(key: key, label: label, items: (items ?? []).map { $0.toDomain() })
    }
}

struct SearchResponseDto: Decodable, Sendable {
    let data: [SearchResultBookDto]?
    let total: Int?
    let page: Int?
    let limit: Int?
    let facets: [FacetGroupDto]?
    let sort: String?
    let spellSuggest: String?

    func toDomain() -> SearchResults {
        SearchResults(
            books: (data ?? []).map { $0.toDomain() },
            total: total ?? 0,
            page: page ?? 1,
            limit: limit ?? 24,
            facets: (facets ?? []).map { $0.toDomain() },
            sort: SearchSortOrder.fromWire(sort),
            spellSuggest: spellSuggest
        )
    }
}

// MARK: - Suggest (typeahead)

struct SuggestBookDto: Decodable, Sendable {
    let id: String
    let slug: String
    let icin: String?
    let title: String
    let authorName: String?
    let coverThumbUrl: String?

    func toDomain() -> SuggestBook {
        SuggestBook(
            id: id, slug: slug, icin: icin, title: title,
            authorName: authorName, coverThumbUrl: coverThumbUrl
        )
    }
}

struct SuggestEntityDto: Decodable, Sendable {
    let id: String
    let slug: String
    let label: String
    let imageUrl: String?
    let bookCount: Int?

    func toDomain() -> SuggestEntity {
        SuggestEntity(
            id: id, slug: slug, label: label,
            imageUrl: imageUrl, bookCount: bookCount
        )
    }
}

struct SuggestTagDto: Decodable, Sendable {
    let id: String
    let slug: String
    let label: String
    let tagType: String
    let icon: String?
    let color: String?

    func toDomain() -> SuggestTag {
        SuggestTag(
            id: id, slug: slug, label: label,
            tagType: TagType.fromWire(tagType) ?? .general,
            icon: icon, color: color
        )
    }
}

struct SuggestResponseDto: Decodable, Sendable {
    let query: String?
    let books: [SuggestBookDto]?
    let authors: [SuggestEntityDto]?
    let series: [SuggestEntityDto]?
    let characters: [SuggestEntityDto]?
    let tags: [SuggestTagDto]?

    func toDomain() -> SuggestResults {
        SuggestResults(
            query: query ?? "",
            books: (books ?? []).map { $0.toDomain() },
            authors: (authors ?? []).map { $0.toDomain() },
            series: (series ?? []).map { $0.toDomain() },
            // characters: backend returns [] until migration 044 lands —
            // ignored here for now per the Phase 2 plan.
            tags: (tags ?? []).map { $0.toDomain() }
        )
    }
}
