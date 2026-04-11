import Foundation

struct CheckoutRepositoryImpl: CheckoutRepository, Sendable {
    private let api: CheckoutAPIService

    init(api: CheckoutAPIService) {
        self.api = api
    }

    func getCart() async throws -> [CartItem] {
        let response = try await api.getCart()
        return response.items.map { $0.toDomain() }
    }

    func addToCart(bookId: String) async throws {
        try await api.addToCart(bookId: bookId)
    }

    func removeFromCart(bookId: String) async throws {
        try await api.removeFromCart(bookId: bookId)
    }

    func clearCart() async throws {
        try await api.clearCart()
    }

    func getCheckoutConfig() async throws -> CheckoutConfig {
        let response = try await api.getCheckoutConfig()
        return response.toDomain()
    }

    func createCheckoutSession() async throws -> URL {
        let response = try await api.createCheckoutSession()
        guard let urlString = response.checkoutUrl, let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        return url
    }

    func mockCheckout() async throws {
        _ = try await api.mockCheckout()
    }
}
