import Foundation

protocol DiscoveryRepository: Sendable {
    func getBrowseHub() async throws -> [BrowseHubGroup]
    func getTrending(limit: Int?) async throws -> [TrendingBook]
    func getRelated(icin: String) async throws -> [RelatedBook]
}
