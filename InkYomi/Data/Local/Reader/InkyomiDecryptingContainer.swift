import Foundation
import ReadiumShared
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "InkyomiDecContainer")

/// A Readium Container that transparently decrypts Inkyomi-protected
/// EPUB resources on read. For any entry whose path is in `encryptedPaths`
/// (from `META-INF/encryption.xml`), reads return AES-256-CBC plaintext
/// using `contentKey`. All other entries pass through unchanged.
///
/// Wire format: [16 bytes IV][AES-256-CBC ciphertext, PKCS#7 padded]
final class InkyomiDecryptingContainer: Container {
    private let source: ReadiumShared.Container
    private let contentKey: Data
    private let encryptedPaths: Set<String>

    /// LRU cache for recently decrypted plaintext (~16 entries).
    private let cache = NSCache<NSString, NSData>()

    init(source: ReadiumShared.Container, contentKey: Data, encryptedPaths: Set<String>) {
        precondition(contentKey.count == 32, "contentKey must be 32 bytes")
        self.source = source
        self.contentKey = contentKey
        self.encryptedPaths = encryptedPaths
        cache.countLimit = 16
        // Also bound by decrypted bytes, not just entry count: 16 large
        // chapters could otherwise pin tens of MB of plaintext. cost is the
        // plaintext length passed at setObject; NSCache evicts to stay under.
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    // sourceURL must be nil so Readium doesn't bypass the container
    var sourceURL: AbsoluteURL? { nil }

    var entries: Set<AnyURL> { source.entries }

    subscript(url: any URLConvertible) -> (any Resource)? {
        guard let inner = source[url] else { return nil }
        let path = url.anyURL.string.removingPrefix("/")
        if encryptedPaths.contains(path) {
            return DecryptingResource(
                inner: inner,
                contentKey: contentKey,
                cacheKey: path,
                cache: cache
            )
        } else {
            return inner
        }
    }
}

// MARK: - Decrypting Resource

/// A Resource that decrypts its underlying ciphertext on first read
/// and serves subsequent reads from the cached plaintext.
private final class DecryptingResource: Resource {
    private let inner: any Resource
    private let contentKey: Data
    private let cacheKey: String
    private let cache: NSCache<NSString, NSData>

    init(inner: any Resource, contentKey: Data, cacheKey: String, cache: NSCache<NSString, NSData>) {
        self.inner = inner
        self.contentKey = contentKey
        self.cacheKey = cacheKey
        self.cache = cache
    }

    var sourceURL: AbsoluteURL? { nil }

    func properties() async -> ReadResult<ResourceProperties> {
        await inner.properties()
    }

    func estimatedLength() async -> ReadResult<UInt64?> {
        // Must report plaintext length; materialise the plaintext once.
        switch await ensurePlaintext() {
        case .success(let data):
            return .success(UInt64(data.count))
        case .failure(let error):
            return .failure(error)
        }
    }

    func stream(
        range: Range<UInt64>?,
        consume: @escaping (Data) -> Void
    ) async -> ReadResult<Void> {
        switch await ensurePlaintext() {
        case .failure(let error):
            return .failure(error)
        case .success(let plaintext):
            let sliced: Data
            if let range {
                let from = Int(range.lowerBound)
                let to = min(Int(range.upperBound), plaintext.count)
                if from >= to {
                    sliced = Data()
                } else {
                    sliced = plaintext[from..<to]
                }
            } else {
                sliced = plaintext
            }
            consume(sliced)
            return .success(())
        }
    }

    func close() {}

    private func ensurePlaintext() async -> ReadResult<Data> {
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            return .success(cached as Data)
        }

        let result = await inner.read()
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let ciphertext):
            do {
                let plaintext = try ContentKeyWrapper.decryptResource(ciphertext, contentKey: contentKey)
                logger.debug("Decrypted path=\(self.cacheKey) cipherLen=\(ciphertext.count) plainLen=\(plaintext.count)")
                cache.setObject(plaintext as NSData, forKey: key, cost: plaintext.count)
                return .success(plaintext)
            } catch {
                logger.error("decryptResource failed for path=\(self.cacheKey) ciphertextLen=\(ciphertext.count): \(error)")
                return .failure(.decoding(error))
            }
        }
    }
}

// MARK: - String extension

private extension String {
    func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }
}
