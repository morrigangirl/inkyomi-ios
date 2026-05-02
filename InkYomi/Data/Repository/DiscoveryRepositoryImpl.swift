import Foundation

struct DiscoveryRepositoryImpl: DiscoveryRepository, Sendable {
    private let api: DiscoveryAPIService

    init(api: DiscoveryAPIService) {
        self.api = api
    }

    func getBrowseHub() async throws -> [BrowseHubGroup] {
        let response = try await api.getBrowseHub()
        return response.groups.map { $0.toDomain() }
    }

    func getTrending(limit: Int? = 12) async throws -> [TrendingBook] {
        let response = try await api.getTrending(limit: limit)
        return response.data.map { $0.toDomain() }
    }

    func getDiscoverHome(trendingLimit: Int? = 12) async throws -> DiscoverHomePayload {
        let response = try await api.getDiscoverHome(trendingLimit: trendingLimit)
        return DiscoverHomePayload(
            landingPage: response.landingPage.toDomain(),
            browseHub: response.browseHub.groups.map { $0.toDomain() },
            trending: response.trending.data.map { $0.toDomain() }
        )
    }

    func getRelated(icin: String) async throws -> [RelatedBook] {
        let response = try await api.getRelated(icin: icin)
        return response.data.map { $0.toDomain() }
    }
}
