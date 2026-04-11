import Foundation

struct DeviceAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func register(request: DeviceRegisterRequest) async throws -> DeviceRegisterResponse {
        try await client.request(Endpoint(
            path: "data/devices/register",
            method: .post,
            body: request
        ))
    }

    func getDevices() async throws -> DeviceListResponse {
        try await client.request(Endpoint(path: "data/devices"))
    }

    func revokeDevice(id: String) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/devices/\(id)",
            method: .delete
        ))
    }
}
