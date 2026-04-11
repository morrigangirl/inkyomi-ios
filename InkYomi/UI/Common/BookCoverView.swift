import SwiftUI

struct BookCoverView: View {
    let url: String?
    let width: CGFloat?
    let height: CGFloat

    /// Resolves a cover URL that may be a relative path (e.g. "/api/covers/...")
    /// against the app's base URL host.
    private var resolvedURL: URL? {
        guard let urlString = url, !urlString.isEmpty else { return nil }
        // If it's already absolute, use it directly
        if let absolute = URL(string: urlString), absolute.scheme != nil {
            return absolute
        }
        // Relative path — resolve against base host
        return URL(string: urlString, relativeTo: URL(string: "https://inkcolors.shop"))
    }

    var body: some View {
        if let imageUrl = resolvedURL {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .frame(width: width, height: height)
                case .failure:
                    placeholder
                default:
                    placeholder
                        .overlay(ProgressView())
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 2)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.inkPrimary.opacity(0.1))
            .frame(width: width, height: height)
            .overlay {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color.inkPrimary.opacity(0.3))
            }
    }
}
