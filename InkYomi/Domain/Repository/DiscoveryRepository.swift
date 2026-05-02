import Foundation

/// Combined Home payload — landing-page + browse-hub + trending in one
/// round trip. Returned by the new `/api/data/discover/home` endpoint.
struct DiscoverHomePayload: Sendable {
    let landingPage: LandingPage
    let browseHub: [BrowseHubGroup]
    let trending: [TrendingBook]
}

protocol DiscoveryRepository: Sendable {
    func getBrowseHub() async throws -> [BrowseHubGroup]
    func getTrending(limit: Int?) async throws -> [TrendingBook]
    func getDiscoverHome(trendingLimit: Int?) async throws -> DiscoverHomePayload
    func getRelated(icin: String) async throws -> [RelatedBook]
}
