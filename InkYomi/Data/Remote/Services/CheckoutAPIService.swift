import Foundation

struct CheckoutAPIService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func getCart() async throws -> CartResponse {
        try await client.request(Endpoint(path: "data/cart"))
    }

    func addToCart(bookId: String) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/cart",
            method: .post,
            body: AddToCartRequest(bookId: bookId)
        ))
    }

    func removeFromCart(bookId: String) async throws {
        try await client.requestVoid(Endpoint(
            path: "data/cart/\(bookId)",
            method: .delete
        ))
    }

    func clearCart() async throws {
        try await client.requestVoid(Endpoint(
            path: "data/cart/clear",
            method: .post
        ))
    }

    func getCheckoutConfig() async throws -> CheckoutConfigResponse {
        try await client.request(Endpoint(path: "checkout/config"))
    }

    func createCheckoutSession() async throws -> CheckoutSessionResponse {
        try await client.request(Endpoint(
            path: "checkout/session",
            method: .post
        ))
    }

    func mockCheckout() async throws -> MockCheckoutResponse {
        try await client.request(Endpoint(
            path: "checkout",
            method: .post
        ))
    }
}
