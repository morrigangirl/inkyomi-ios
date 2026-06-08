import Foundation
import ReadiumZIPFoundation
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "LendingDownload")

/// Downloads LCP-protected EPUBs and injects the license document
/// (license.lcpl) into the EPUB ZIP for Readium to consume.
final class LendingDownloadManager: @unchecked Sendable {

    /// Directory for lending EPUB storage.
    private var lendingDir: URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lending", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns the path where a lending EPUB would be cached.
    /// Uses .epub extension — NOT .lcpdf. Readium sniffs format from extension,
    /// and .lcpdf would cause it to look for manifest.json and fail.
    func getLendingBookFile(loanId: String) -> URL {
        lendingDir.appendingPathComponent("\(loanId).epub")
    }

    /// Downloads the protected EPUB from the content link, injects the
    /// LCP license into META-INF/license.lcpl, and returns the final file path.
    func downloadAndInjectLicense(
        downloadUrl: String,
        loanId: String,
        licenseData: Data,
        tokenProvider: (@Sendable () async -> String?)?
    ) async throws -> URL {
        guard let url = URL(string: downloadUrl) else {
            throw LendingDownloadError.invalidURL
        }

        let tempFile = lendingDir.appendingPathComponent("\(loanId).epub.tmp")
        let finalFile = getLendingBookFile(loanId: loanId)

        // Download the protected EPUB with auth token
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        if let tokenProvider, let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Stream the response straight to disk instead of buffering the whole
        // EPUB (up to the 100 MB backend cap) in memory — a 100 MB in-memory
        // Data is real jetsam pressure on a low-RAM device (audit C6).
        let (downloadedURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            try? FileManager.default.removeItem(at: downloadedURL)
            throw LendingDownloadError.httpError(statusCode)
        }

        if FileManager.default.fileExists(atPath: tempFile.path) {
            try FileManager.default.removeItem(at: tempFile)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: tempFile)

        // Inject license.lcpl into the EPUB ZIP
        try await injectLicense(sourceEpub: tempFile, targetFile: finalFile, licenseData: licenseData)
        try? FileManager.default.removeItem(at: tempFile)

        // Exclude from iCloud backup
        var mutableURL = finalFile
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(resourceValues)

        logger.info("Downloaded and prepared lending EPUB for loanId=\(loanId)")
        return finalFile
    }

    /// Rebuilds the EPUB ZIP from scratch with the license injected at
    /// META-INF/license.lcpl. Matches the Android approach: read source
    /// entries, write mimetype STORED first, copy all other entries, then
    /// append the license. In-place Archive.addEntry() corrupts the ZIP
    /// central directory, causing Readium to see an empty reading order.
    private func injectLicense(
        sourceEpub: URL,
        targetFile: URL,
        licenseData: Data
    ) async throws {
        if FileManager.default.fileExists(atPath: targetFile.path) {
            try FileManager.default.removeItem(at: targetFile)
        }

        let source = try await Archive(url: sourceEpub, accessMode: .read)
        let target = try await Archive(url: targetFile, accessMode: .create)

        let tempDir = lendingDir.appendingPathComponent("_rebuild_tmp", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entries = try await source.entries()

        // 1. Write mimetype first, uncompressed (EPUB spec requirement)
        if let mimetypeEntry = entries.first(where: { $0.path == "mimetype" }) {
            let mimeData = try await extractToData(archive: source, entry: mimetypeEntry, tempDir: tempDir)
            try await addDataEntry(to: target, path: "mimetype", data: mimeData, type: .file, compressionMethod: .none)
        }

        // 2. Copy all other entries (skip mimetype and any existing license)
        for entry in entries {
            let name = entry.path
            if name == "mimetype" || name == "META-INF/license.lcpl" { continue }
            if entry.type == .directory { continue }

            let entryData = try await extractToData(archive: source, entry: entry, tempDir: tempDir)
            try await addDataEntry(to: target, path: name, data: entryData, type: entry.type)
        }

        // 3. Inject license.lcpl
        try await addDataEntry(to: target, path: "META-INF/license.lcpl", data: licenseData, type: .file)
    }

    /// Extract an entry to a temp file and return it memory-mapped.
    /// `.mappedIfSafe` keeps the entry's bytes file-backed (paged in on demand,
    /// evictable under memory pressure) rather than fully resident, so a single
    /// large ZIP entry can't spike memory during the rebuild (audit C6). The
    /// mapping stays valid after the temp file is unlinked — POSIX keeps the
    /// inode alive until the mapping is released. Also avoids Sendable issues
    /// with the consumer-based extract API.
    private func extractToData(archive: Archive, entry: Entry, tempDir: URL) async throws -> Data {
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
        _ = try await archive.extract(entry, to: tempFile, skipCRC32: true)
        let data = try Data(contentsOf: tempFile, options: .mappedIfSafe)
        try? FileManager.default.removeItem(at: tempFile)
        return data
    }

    private func addDataEntry(
        to archive: Archive,
        path: String,
        data: Data,
        type: Entry.EntryType,
        compressionMethod: CompressionMethod = .deflate
    ) async throws {
        let bytes = data
        try await archive.addEntry(
            with: path,
            type: type,
            uncompressedSize: Int64(bytes.count),
            compressionMethod: compressionMethod,
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, bytes.count)
                return bytes[start..<end]
            }
        )
    }

    /// Deletes a cached lending EPUB.
    func deleteLendingBook(loanId: String) {
        let file = getLendingBookFile(loanId: loanId)
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: file)
            logger.info("Deleted lending EPUB for loanId=\(loanId)")
        }
    }
}

enum LendingDownloadError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case emptyResponse
    case noPublicationLink

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid download URL"
        case .httpError(let code): "Download failed: HTTP \(code)"
        case .emptyResponse: "Empty response body"
        case .noPublicationLink: "No publication link in license"
        }
    }
}
