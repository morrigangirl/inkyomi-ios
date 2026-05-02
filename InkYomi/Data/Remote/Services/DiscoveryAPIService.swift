import Foundation

/// Discovery endpoints introduced by pearlescent-dream commit 8bbe9e3
/// (Phase 1: search FTS + faceted discovery + categorization UI). All
/// endpoints are public (no auth required) and serve their content with
/// `Cache-Control: public, max-age=60, s-maxage=60, stale-while-revalidate=300`.
struct DiscoveryAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getBrowseHub() async throws -> BrowseHubResponseDto {
        try await client.request(Endpoint(path: "data/categories/browse-hub"))
    }

    func getTrending(tagSlug: String? = nil, window: String? = nil, limit: Int? = nil) async throws -> TrendingResponseDto {
        var items: [URLQueryItem] = []
        if let tagSlug { items.append(URLQueryItem(name: "tagSlug", value: tagSlug)) }
        if let window { items.append(URLQueryItem(name: "window", value: window)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await client.request(Endpoint(
            path: "data/books/trending",
            queryItems: items.isEmpty ? nil : items
        ))
    }

    /// Combined Home payload — landing-page + browse-hub + trending in
    /// one round trip. Returns failure (404 / 5xx) when the route isn't
    /// deployed yet; `HomeViewModel` falls back to the per-endpoint
    /// fanout in that case.
    func getDiscoverHome(trendingLimit: Int? = nil) async throws -> DiscoverHomeResponseDto {
        var items: [URLQueryItem] = []
        if let trendingLimit { items.append(URLQueryItem(name: "trendingLimit", value: String(trendingLimit))) }
        return try await client.request(Endpoint(
            path: "data/discover/home",
            queryItems: items.isEmpty ? nil : items
        ))
    }

    /// "More like this" — Jaccard tag overlap + series/author boost.
    func getRelated(icin: String) async throws -> RelatedBookResponseDto {
        try await client.request(Endpoint(path: "data/books/\(icin)/related"))
    }
}
