import Foundation

struct ReaderAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getDownloadUrl(bookId: String, artifactType: String = "retail_download") async throws -> DownloadArtifactResponse {
        try await client.request(Endpoint(
            path: "download-artifact",
            method: .post,
            body: DownloadArtifactRequest(bookId: bookId, artifactType: artifactType)
        ))
    }
}
