import Foundation

struct SpanTelemetryAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getAccountingManifest(loanId: String) async throws -> AccountingManifestResponse {
        try await client.request(Endpoint(
            path: "telemetry/loans/\(loanId)/accounting-manifest"
        ))
    }

    func uploadSpans(request: SpanUploadRequest) async throws -> SpanUploadResponse {
        try await client.request(Endpoint(
            path: "telemetry/spans",
            method: .post,
            body: request
        ))
    }
}
