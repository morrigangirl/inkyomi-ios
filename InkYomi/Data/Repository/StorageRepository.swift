import Foundation

struct StorageStats: Sendable {
    let ownedBytes: Int64
    let ownedCount: Int
    let borrowedBytes: Int64
    let borrowedCount: Int

    var totalBytes: Int64 { ownedBytes + borrowedBytes }
}

/// Computes and clears local reading-download caches. Borrowed-book EPUBs
/// live in `Documents/lending/`, owned-book EPUBs live in `Documents/books/`.
/// Clearing is safe: the reader's open path re-downloads from the server on
/// next open, and per-loan transport secrets remain in the Keychain so
/// decryption still works after a clear.
actor StorageRepository {

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func stats() -> StorageStats {
        let owned = directoryStats(at: ownedDirectory())
        let borrowed = directoryStats(at: borrowedDirectory())
        return StorageStats(
            ownedBytes: owned.bytes,
            ownedCount: owned.count,
            borrowedBytes: borrowed.bytes,
            borrowedCount: borrowed.count
        )
    }

    @discardableResult
    func clearBorrowed() -> Int64 {
        return deleteDirectoryContents(at: borrowedDirectory())
    }

    /// Wipes both owned and borrowed download caches. Called from the
    /// "Remove this device" flow + the bounce-to-OAuth migration
    /// path — anywhere we have to drop every byte tied to the
    /// signed-in user. Returns total bytes freed.
    @discardableResult
    func clearAllDownloads() -> Int64 {
        let borrowed = deleteDirectoryContents(at: borrowedDirectory())
        let owned = deleteDirectoryContents(at: ownedDirectory())
        return borrowed + owned
    }

    // MARK: - Internals

    private func ownedDirectory() -> URL {
        documents().appendingPathComponent("books", isDirectory: true)
    }

    private func borrowedDirectory() -> URL {
        documents().appendingPathComponent("lending", isDirectory: true)
    }

    private func documents() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private struct DirSummary { let bytes: Int64; let count: Int }

    private func directoryStats(at url: URL) -> DirSummary {
        var bytes: Int64 = 0
        var count = 0
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        while let item = enumerator?.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                count += 1
                bytes += Int64(values?.fileSize ?? 0)
            }
        }
        return DirSummary(bytes: bytes, count: count)
    }

    @discardableResult
    private func deleteDirectoryContents(at url: URL) -> Int64 {
        var freed: Int64 = 0
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        while let item = enumerator?.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                freed += Int64(values?.fileSize ?? 0)
                try? fileManager.removeItem(at: item)
            }
        }
        return freed
    }
}

extension StorageStats {
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
