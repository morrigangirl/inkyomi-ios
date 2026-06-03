import SwiftUI
import WebKit

/// Pre-purchase "Look Inside" preview sheet. Renders the server-sanitized
/// `preview_html` excerpt in a JavaScript-disabled `WKWebView`. This is a
/// plain HTML excerpt — it deliberately does NOT go through the
/// Readium/DRM reader.
struct LookInsideView: View {
    let idOrSlug: String
    let bookTitle: String
    /// Owned by the parent `BookDetailView`; the sheet reads its
    /// Look Inside state and triggers the on-demand fetch. Observed
    /// automatically via the Observation framework.
    let viewModel: BookDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingLookInside {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let preview = viewModel.lookInsidePreview {
                    PreviewWebView(html: preview.previewHtml)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "No preview",
                        systemImage: "book.closed",
                        description: Text("This book doesn't have a preview yet.")
                    )
                }
            }
            .navigationTitle(viewModel.lookInsidePreview?.sourceTitle ?? bookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.loadLookInside(idOrSlug: idOrSlug)
            }
        }
    }
}

/// A `WKWebView` with JavaScript disabled, used only to display the
/// already-sanitized Look Inside excerpt. No navigation, no JS, no DRM.
private struct PreviewWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Hard-disable JavaScript — this is a static HTML excerpt.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // No injected scripts / message handlers.
        configuration.userContentController = WKUserContentController()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(Self.wrap(html), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Static content; nothing to update after the initial load.
    }

    /// Wrap the sanitized fragment in a responsive, dark-mode-aware
    /// document with a readable system-font body. The fragment itself is
    /// trusted to be sanitized server-side; we add only presentation.
    private static func wrap(_ fragment: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body {
            font: -apple-system-body;
            font-family: -apple-system, system-ui, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 16px 18px 32px;
            -webkit-text-size-adjust: 100%;
          }
          img { max-width: 100%; height: auto; }
          h1, h2, h3 { line-height: 1.25; }
          p { margin: 0 0 1em; }
        </style>
        </head>
        <body>\(fragment)</body>
        </html>
        """
    }
}
