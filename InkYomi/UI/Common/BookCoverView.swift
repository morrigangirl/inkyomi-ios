import SwiftUI
import CryptoKit

struct BookCoverView: View {
    let url: String?
    let width: CGFloat?
    let height: CGFloat

    /// Resolves a cover URL that may be a relative path (e.g. "/api/covers/...")
    /// against the app's base URL host.
    private var resolvedURL: URL? {
        guard let urlString = url, !urlString.isEmpty else { return nil }
        if let absolute = URL(string: urlString), absolute.scheme != nil {
            return absolute
        }
        return URL(string: urlString, relativeTo: URL(string: "https://inkcolors.shop"))
    }

    var body: some View {
        if let imageUrl = resolvedURL {
            CachedAsyncImage(url: imageUrl) { phase in
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

// MARK: - File-based Image Cache

struct CachedAsyncImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: url) {
                await load()
            }
    }

    private func load() async {
        // 1. Check file cache
        if let uiImage = CoverDiskCache.shared.load(for: url) {
            phase = .success(Image(uiImage: uiImage))
            return
        }

        // 2. Download and cache to disk
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            CoverDiskCache.shared.save(data, for: url)
            phase = .success(Image(uiImage: uiImage))
        } catch {
            if !Task.isCancelled {
                phase = .failure(error)
            }
        }
    }
}

/// Saves cover images to Caches/covers/ keyed by URL hash.
/// Files in Caches/ survive app restarts but the OS can purge them under storage pressure.
final class CoverDiskCache: @unchecked Sendable {
    static let shared = CoverDiskCache()

    private let cacheDir: URL
    private let memoryCache = NSCache<NSString, UIImage>()

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memoryCache.countLimit = 80
    }

    private func cacheFile(for url: URL) -> URL {
        let hash = Insecure.MD5.hash(data: Data(url.absoluteString.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(hex)
    }

    func load(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let file = cacheFile(for: url)
        guard let data = try? Data(contentsOf: file),
              let image = UIImage(data: data) else { return nil }
        memoryCache.setObject(image, forKey: key)
        return image
    }

    func save(_ data: Data, for url: URL) {
        let file = cacheFile(for: url)
        try? data.write(to: file, options: .atomic)
        if let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: url.absoluteString as NSString)
        }
    }
}
