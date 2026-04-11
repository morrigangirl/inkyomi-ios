import Foundation
import Observation

@Observable
final class DeepLinkHandler {
    var pendingCheckoutResult: CheckoutResult?

    enum CheckoutResult {
        case success
        case cancel
    }

    func handle(_ url: URL) {
        guard url.scheme == Constants.URLScheme.scheme else { return }

        let fullString = url.absoluteString
        if fullString.hasPrefix(Constants.URLScheme.checkoutSuccess) {
            pendingCheckoutResult = .success
        } else if fullString.hasPrefix(Constants.URLScheme.checkoutCancel) {
            pendingCheckoutResult = .cancel
        }
    }

    func consumeCheckoutResult() -> CheckoutResult? {
        let result = pendingCheckoutResult
        pendingCheckoutResult = nil
        return result
    }
}
