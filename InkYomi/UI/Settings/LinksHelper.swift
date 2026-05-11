import Foundation
import SwiftUI
import SafariServices
import UIKit

/// Centralised URLs and email addresses surfaced from Settings. Hosting on
/// inkcolors.shop is the canonical home for legal pages.
enum InkColorsLinks {
    static let privacyURL = URL(string: "https://inkcolors.shop/privacy")!
    static let termsURL = URL(string: "https://inkcolors.shop/terms")!
    static let supportEmail = "support@inkcolors.shop"
    static let privacyEmail = "privacy@inkcolors.shop"
    static let websiteURL = URL(string: "https://inkcolors.shop")!

    /// Canonical public book page on inkcolors.shop, e.g.
    /// `https://inkcolors.shop/books/US-J46BK79SN1`. Falls back to the
    /// site root when no ICIN is available.
    static func bookURL(icin: String?) -> URL {
        guard
            let icin,
            let encoded = icin.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://inkcolors.shop/books/\(encoded)")
        else {
            return websiteURL
        }
        return url
    }
}

/// Drop-in `SafariServices.SFSafariViewController` wrapper. Used for
/// in-app rendering of Privacy Policy / Terms of Service URLs (matches
/// the Android Custom Tabs experience).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Color.inkPrimary)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

enum MailtoComposer {
    /// Build a `mailto:` URL with optional subject and body.
    static func url(to address: String, subject: String? = nil, body: String? = nil) -> URL? {
        var components = URLComponents(string: "mailto:\(address)")
        var items: [URLQueryItem] = []
        if let subject { items.append(URLQueryItem(name: "subject", value: subject)) }
        if let body { items.append(URLQueryItem(name: "body", value: body)) }
        if !items.isEmpty { components?.queryItems = items }
        return components?.url
    }

    /// Open the system mail composer (or the system-resolved fallback) for
    /// the given address with optional subject + body. Best-effort — silent
    /// no-op if the URL cannot be opened.
    @MainActor
    static func open(_ address: String, subject: String? = nil, body: String? = nil) {
        guard let url = url(to: address, subject: subject, body: body) else { return }
        UIApplication.shared.open(url)
    }
}
