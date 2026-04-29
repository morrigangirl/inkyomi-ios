import Foundation

/// Mirrors the backend `TagType` from `@inkcolors/contracts`. The 8 tag
/// types plus the special facet keys returned by `/api/search/v2`.
enum TagType: String, CaseIterable, Sendable, Hashable, Codable {
    case identity
    case genre
    case subgenre
    case trope
    case tone
    case outcome
    case contentFlag = "content_flag"
    case general

    /// The value the backend emits on the wire (the raw value mirrors
    /// it, save for `contentFlag`'s snake-cased override).
    var wire: String { rawValue }

    static func fromWire(_ value: String?) -> TagType? {
        guard let value else { return nil }
        return TagType.allCases.first { $0.wire == value }
    }
}

/// Matches `SearchSortOrder` in the backend contracts.
enum SearchSortOrder: String, CaseIterable, Sendable, Hashable, Codable {
    case relevance
    case newest
    case oldest
    case priceAsc
    case priceDesc
    case rating
    case popularity
    case titleAsc

    var wire: String { rawValue }

    var label: String {
        switch self {
        case .relevance: "Relevance"
        case .newest:    "Newest"
        case .oldest:    "Oldest"
        case .priceAsc:  "Price: Low to High"
        case .priceDesc: "Price: High to Low"
        case .rating:    "Top Rated"
        case .popularity:"Most Popular"
        case .titleAsc:  "Title: A–Z"
        }
    }

    static func fromWire(_ value: String?) -> SearchSortOrder {
        SearchSortOrder.allCases.first { $0.wire == value } ?? .relevance
    }
}

/// One column in the facet sidebar — a tag type or a computed dimension.
/// The wire `key` matches `FacetKey` in the contracts.
struct FacetGroup: Identifiable, Sendable, Hashable {
    let key: String
    let label: String
    let items: [FacetItem]

    var id: String { key }
}

struct FacetItem: Identifiable, Sendable, Hashable {
    let value: String
    let label: String
    let count: Int
    let color: String?
    let icon: String?

    var id: String { value }
}

/// Filter state. Tag slugs are grouped by tag type (AND across types, OR
/// within a type per the backend contract). Other filters are flat.
struct SearchFilters: Sendable, Equatable {
    var tagSlugs: [TagType: [String]] = [:]
    var authorId: String? = nil
    var seriesId: String? = nil
    var characterId: String? = nil
    var priceMin: Double? = nil
    var priceMax: Double? = nil
    var ratingMin: Double? = nil
    var language: [String] = []
    var hasContentWarning: Bool? = nil
    var spiceLevelMax: Int? = nil

    var isEmpty: Bool {
        tagSlugs.values.allSatisfy { $0.isEmpty } &&
            authorId == nil && seriesId == nil && characterId == nil &&
            priceMin == nil && priceMax == nil && ratingMin == nil &&
            language.isEmpty && hasContentWarning == nil && spiceLevelMax == nil
    }

    /// Total number of selected items across all dimensions, for the
    /// active-filter badge.
    var activeCount: Int {
        var n = tagSlugs.values.reduce(0) { $0 + $1.count } + language.count
        if authorId != nil { n += 1 }
        if seriesId != nil { n += 1 }
        if characterId != nil { n += 1 }
        if priceMin != nil { n += 1 }
        if priceMax != nil { n += 1 }
        if ratingMin != nil { n += 1 }
        if hasContentWarning != nil { n += 1 }
        if spiceLevelMax != nil { n += 1 }
        return n
    }

    func toggleTag(type: TagType, slug: String) -> SearchFilters {
        var copy = self
        var current = copy.tagSlugs[type] ?? []
        if let idx = current.firstIndex(of: slug) {
            current.remove(at: idx)
        } else {
            current.append(slug)
        }
        if current.isEmpty {
            copy.tagSlugs.removeValue(forKey: type)
        } else {
            copy.tagSlugs[type] = current
        }
        return copy
    }
}

/// Richer book projection returned by `/api/search/v2`. Adds search-only
/// fields (subtitle, hook, spice level, series_name/number) on top of
/// the basic catalog `Book`.
struct SearchResultBook: Identifiable, Sendable, Hashable {
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
    let isPurchasable: Bool
    let isNewRelease: Bool
    let isFeatured: Bool
    let hasContentWarning: Bool
    let spiceLevel: Int?
    let language: String?
    let ratingAvg: Double?
    let ratingCount: Int?
    let seriesName: String?
    let seriesNumber: String?
}

struct SearchResults: Sendable {
    let books: [SearchResultBook]
    let total: Int
    let page: Int
    let limit: Int
    let facets: [FacetGroup]
    let sort: SearchSortOrder
    let spellSuggest: String?
}

// MARK: - Suggest (typeahead)

struct SuggestBook: Identifiable, Sendable {
    let id: String
    let slug: String
    let icin: String?
    let title: String
    let authorName: String?
    let coverThumbUrl: String?
}

struct SuggestEntity: Identifiable, Sendable {
    let id: String
    let slug: String
    let label: String
    let imageUrl: String?
    let bookCount: Int?
}

struct SuggestTag: Identifiable, Sendable {
    let id: String
    let slug: String
    let label: String
    let tagType: TagType
    let icon: String?
    let color: String?
}

struct SuggestResults: Sendable {
    let query: String
    let books: [SuggestBook]
    let authors: [SuggestEntity]
    let series: [SuggestEntity]
    let tags: [SuggestTag]

    var isEmpty: Bool {
        books.isEmpty && authors.isEmpty && series.isEmpty && tags.isEmpty
    }
}
