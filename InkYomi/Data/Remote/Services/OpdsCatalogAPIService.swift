import Foundation

struct OpdsCatalogAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getCatalog(query: String? = nil) async throws -> OpdsFeed {
        var queryItems: [URLQueryItem]? = nil
        if let q = query, !q.isEmpty {
            queryItems = [URLQueryItem(name: "q", value: q)]
        }
        return try await client.request(Endpoint(
            path: "opds/catalog",
            queryItems: queryItems
        ))
    }

    func getPublication(id: String) async throws -> OpdsPublication {
        try await client.request(Endpoint(
            path: "opds/publications/\(id)"
        ))
    }

    func getShelf() async throws -> OpdsFeed {
        try await client.request(Endpoint(
            path: "opds/shelf"
        ))
    }
}
