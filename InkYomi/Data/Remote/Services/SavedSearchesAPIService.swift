import Foundation

/// Backend saved-searches CRUD. All endpoints require the bearer token
/// (`authenticate` middleware on the server side); the APIClient handles
/// the auth header injection.
struct SavedSearchesAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func list() async throws -> SavedSearchListResponseDto {
        try await client.request(Endpoint(path: "data/saved-searches"))
    }

    func create(_ request: CreateSavedSearchRequestDto) async throws -> SavedSearchDto {
        try await client.request(Endpoint(
            path: "data/saved-searches",
            method: .post,
            body: request
        ))
    }

    func update(id: String, _ request: UpdateSavedSearchRequestDto) async throws -> SavedSearchDto {
        try await client.request(Endpoint(
            path: "data/saved-searches/\(id)",
            method: .patch,
            body: request
        ))
    }

    func delete(id: String) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/saved-searches/\(id)",
            method: .delete
        ))
    }
}
