import Foundation

/// Backend search v2 — full-text search + faceted filters + typeahead.
/// Mounted at `/api/search/v2` in pearlescent-dream's `search-books.ts`.
/// The route accepts repeatable query parameters per `tag_type`
/// (`?genre=fantasy&genre=romance`).
struct SearchAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func search(
        query: String?,
        sort: SearchSortOrder?,
        page: Int?,
        limit: Int?,
        filters: SearchFilters
    ) async throws -> SearchResponseDto {
        var items: [URLQueryItem] = []
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let sort {
            items.append(URLQueryItem(name: "sort", value: sort.wire))
        }
        if let page {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        // 8 tag-type axes, repeatable.
        for type in TagType.allCases {
            for slug in filters.tagSlugs[type] ?? [] {
                items.append(URLQueryItem(name: type.wire, value: slug))
            }
        }
        if let authorId = filters.authorId {
            items.append(URLQueryItem(name: "authorId", value: authorId))
        }
        if let seriesId = filters.seriesId {
            items.append(URLQueryItem(name: "seriesId", value: seriesId))
        }
        if let characterId = filters.characterId {
            items.append(URLQueryItem(name: "characterId", value: characterId))
        }
        if let priceMin = filters.priceMin {
            items.append(URLQueryItem(name: "priceMin", value: String(priceMin)))
        }
        if let priceMax = filters.priceMax {
            items.append(URLQueryItem(name: "priceMax", value: String(priceMax)))
        }
        if let ratingMin = filters.ratingMin {
            items.append(URLQueryItem(name: "ratingMin", value: String(ratingMin)))
        }
        for lang in filters.language {
            items.append(URLQueryItem(name: "language", value: lang))
        }
        if let hcw = filters.hasContentWarning {
            items.append(URLQueryItem(name: "hasContentWarning", value: hcw ? "true" : "false"))
        }
        if let spice = filters.spiceLevelMax {
            items.append(URLQueryItem(name: "spiceLevelMax", value: String(spice)))
        }

        return try await client.request(Endpoint(
            path: "search/v2",
            queryItems: items.isEmpty ? nil : items
        ))
    }

    func suggest(query: String) async throws -> SuggestResponseDto {
        try await client.request(Endpoint(
            path: "search/v2/suggest",
            queryItems: [URLQueryItem(name: "q", value: query)]
        ))
    }
}
