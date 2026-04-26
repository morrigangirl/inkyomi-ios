import SwiftUI

/// Renders limited HTML (bold, italic, links, paragraphs, line breaks)
/// as an AttributedString for display in SwiftUI Text views.
struct HTMLTextView: View {
    let html: String

    var body: some View {
        if let attributed = renderHTML(html) {
            Text(attributed)
                .font(.body)
        } else {
            Text(html)
                .font(.body)
        }
    }

    private func renderHTML(_ html: String) -> AttributedString? {
        // Wrap in a basic HTML document with body font styling
        let wrapped = """
        <html><head><style>
        body { font-family: -apple-system; font-size: 16px; }
        </style></head><body>\(html)</body></html>
        """
        guard let data = wrapped.data(using: .utf8),
              let nsAttr = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              )
        else { return nil }
        // The HTML parser bakes black foreground/white background into every
        // character. Strip them so the SwiftUI .foregroundStyle on the wrapper
        // (and the system's dark-mode handling) takes effect.
        let range = NSRange(location: 0, length: nsAttr.length)
        nsAttr.removeAttribute(.foregroundColor, range: range)
        nsAttr.removeAttribute(.backgroundColor, range: range)
        return try? AttributedString(nsAttr, including: \.uiKit)
    }
}
