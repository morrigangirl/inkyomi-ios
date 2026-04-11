import Foundation

protocol CheckoutRepository: Sendable {
    func getCart() async throws -> [CartItem]
    func addToCart(bookId: String) async throws
    func removeFromCart(bookId: String) async throws
    func clearCart() async throws
    func getCheckoutConfig() async throws -> CheckoutConfig
    func createCheckoutSession() async throws -> URL
    func mockCheckout() async throws
}
