import Foundation

struct OpdsLendingAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func borrowBook(bookId: String) async throws -> BorrowResponse {
        try await client.request(Endpoint(
            path: "opds/publications/\(bookId)/borrow",
            method: .post
        ))
    }

    func getLicense(loanId: String) async throws -> LcpLicenseDocument {
        try await client.request(Endpoint(
            path: "licenses/\(loanId).lcpl"
        ))
    }

    /// Returns the raw license JSON bytes — must be injected into the EPUB
    /// as-is so the RSA signature remains valid. Never round-trip through a DTO.
    func getLicenseRaw(loanId: String) async throws -> Data {
        try await client.requestData(Endpoint(
            path: "licenses/\(loanId).lcpl"
        ))
    }

    func getTransportSecret(loanId: String) async throws -> TransportSecretResponse {
        try await client.request(Endpoint(
            path: "licenses/\(loanId)/transport-secret"
        ))
    }

    func getLoanStatus(loanId: String) async throws -> LsdStatusDocument {
        try await client.request(Endpoint(
            path: "licenses/\(loanId)/status"
        ))
    }

    func returnBook(loanId: String) async throws -> LsdStatusDocument {
        try await client.request(Endpoint(
            path: "licenses/\(loanId)/return",
            method: .put,
            queryItems: await deviceQueryItems()
        ))
    }

    func renewBook(loanId: String) async throws -> LsdStatusDocument {
        try await client.request(Endpoint(
            path: "licenses/\(loanId)/renew",
            method: .put,
            queryItems: await deviceQueryItems()
        ))
    }

    func registerDevice(loanId: String) async throws {
        try await client.requestVoid(Endpoint(
            path: "licenses/\(loanId)/register",
            method: .post,
            queryItems: await deviceQueryItems()
        ))
    }

    /// The LSD register/return/renew routes identify the device from the `id`
    /// query param (`req.query.id ?? req.body?.id`) and ignore the X-Device-Id
    /// header these calls otherwise carry. Without `id` the server records a
    /// NULL device against the loan, so thread the stable device id through.
    private func deviceQueryItems() async -> [URLQueryItem]? {
        guard let provider = await client.deviceIdProvider,
              let deviceId = await provider() else { return nil }
        return [URLQueryItem(name: "id", value: deviceId)]
    }
}
