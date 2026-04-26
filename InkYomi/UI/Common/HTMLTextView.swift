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
              let nsAttr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              )
        else { return nil }
        return try? AttributedString(nsAttr, including: \.uiKit)
    }
}
