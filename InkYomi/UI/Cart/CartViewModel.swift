import Foundation
import Observation

@MainActor @Observable
final class CartViewModel {
    var items: [CartItem] = []
    var isLoading = false
    var error: String?
    var checkoutURL: URL?
    var showCheckout = false

    private var checkoutRepository: (any CheckoutRepository)?

    var total: Double {
        items.reduce(0) { $0 + $1.priceUsd }
    }

    func configure(checkoutRepository: any CheckoutRepository) {
        self.checkoutRepository = checkoutRepository
    }

    func loadCart() async {
        guard let checkoutRepository else { return }
        isLoading = true
        do {
            items = try await checkoutRepository.getCart()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func removeItem(bookId: String) async {
        guard let checkoutRepository else { return }
        do {
            try await checkoutRepository.removeFromCart(bookId: bookId)
            items.removeAll { $0.bookId == bookId }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func checkout() async {
        guard let checkoutRepository else { return }
        do {
            let config = try await checkoutRepository.getCheckoutConfig()
            if config.mode == .live {
                checkoutURL = try await checkoutRepository.createCheckoutSession()
                showCheckout = true
            } else {
                try await checkoutRepository.mockCheckout()
                items = []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
