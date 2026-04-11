import Foundation
import ReadiumShared
import SwiftData
import os.log

private let logger = Logger(subsystem: "shop.inkcolors.InkYomi", category: "InkyomiDRM")

/// Self-hosted Inkyomi DRM (LCP-equivalent) ContentProtection.
///
/// When a publication is opened, this protection checks for `META-INF/license.lcpl`.
/// If found, it:
///  1. Parses the license document
///  2. Re-verifies the RSA signature against the bundled provider public key
///  3. Resolves the local loan record and fetches the per-loan transport secret
///  4. Derives the transport key and unwraps the AES-256 content key
///  5. Parses `META-INF/encryption.xml` for encrypted resource paths
///  6. Wraps the container in InkyomiDecryptingContainer for transparent decryption
final class InkyomiContentProtection: ContentProtection {

    private let modelContainer: ModelContainer
    private let transportSecretStore: LcpTransportSecretStore
    private let providerCertStore: ProviderCertStore

    /// Must match the server's `info` string for the user-side wrap.
    private static let infoUserWrap = "inkyomi/v1/user-wrap"

    init(
        modelContainer: ModelContainer,
        transportSecretStore: LcpTransportSecretStore,
        providerCertStore: ProviderCertStore = .shared
    ) {
        self.modelContainer = modelContainer
        self.transportSecretStore = transportSecretStore
        self.providerCertStore = providerCertStore
    }

    func open(
        asset: Asset,
        credentials: String?,
        allowUserInteraction: Bool,
        sender: Any?
    ) async -> Result<ContentProtectionAsset, ContentProtectionOpenError> {
        // Only handle container assets (EPUBs in a ZIP)
        guard case .container(var containerAsset) = asset else {
            debugLog("ContentProtection: not a container asset, skipping")
            return .failure(.assetNotSupported(nil))
        }
        let container = containerAsset.container
        debugLog("ContentProtection: container has \(container.entries.count) entries, sourceURL=\(String(describing: container.sourceURL))")

        // ---- 1. Sniff license.lcpl ----
        guard let licenseUrl = AnyURL(string: "META-INF/license.lcpl") else {
            debugLog("ContentProtection: could not create license URL")
            return .failure(.assetNotSupported(nil))
        }
        guard let licenseResource = container[licenseUrl] else {
            // No license file → not a borrowed book, pass through
            debugLog("ContentProtection: no license.lcpl found, passing through")
            return .failure(.assetNotSupported(nil))
        }
        debugLog("ContentProtection: found license.lcpl, reading...")
        let licenseResult = await licenseResource.read()
        let licenseBytes: Data
        switch licenseResult {
        case .success(let data):
            licenseBytes = data
        case .failure:
            return .failure(.assetNotSupported(nil))
        }

        // ---- 2. Parse license + verify signature (fail-closed) ----
        guard let licenseJsonString = String(data: licenseBytes, encoding: .utf8) else {
            return .failure(.assetNotSupported(nil))
        }

        let license: LcpLicenseDocument
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            license = try decoder.decode(LcpLicenseDocument.self, from: licenseBytes)
            debugLog("ContentProtection: parsed license id=\(license.id)")
        } catch {
            debugLog("ContentProtection: failed to parse license.lcpl: \(error)")
            logger.error("Failed to parse license.lcpl: \(error)")
            return .failure(.assetNotSupported(nil))
        }

        guard let sigValue = license.signature?.value else {
            return failClosed("License missing signature.value")
        }

        do {
            let publicKey = try providerCertStore.publicKey()
            let verified = LicenseSignatureVerifier.verify(
                jsonData: licenseBytes,
                signatureB64: sigValue,
                publicKey: publicKey
            )
            guard verified else {
                return failClosed("License signature did not verify (tampered or wrong provider key)")
            }
        } catch {
            return failClosed("Signature verifier threw: \(error)")
        }

        // ---- 3. Resolve loan + transport secret ----
        let statusHref = license.links.first { $0.rel == "status" }?.href
        let derivedLoanId = statusHref?
            .components(separatedBy: "/licenses/").last?
            .components(separatedBy: "/status").first

        let mc = self.modelContainer
        let tss = self.transportSecretStore
        let loanId = await Self.findLoanId(
            derivedLoanId: derivedLoanId,
            licenseId: license.id,
            modelContainer: mc
        )
        guard let loanId else {
            logger.warning("Inkyomi license recognised but no local loan for licenseId=\(license.id)")
            return .failure(.assetNotSupported(nil))
        }

        guard let transportSecretHex = tss.getTransportSecretHex(loanId) else {
            return failClosed("Missing transport_secret for loanId=\(loanId)")
        }

        // ---- 4. Derive transport key + unwrap content key ----
        let contentKey: Data
        do {
            let transportSecret = hexToBytes(transportSecretHex)
            let transportKey = TransportKey.derive(transportSecret: transportSecret, licenseId: license.id)

            guard let encryptedValue = license.encryption.contentKey.encryptedValue,
                  let iv = license.encryption.contentKey.iv,
                  let mac = license.encryption.contentKey.mac else {
                return failClosed("License encryption.content_key fields missing")
            }

            let wrapped = ContentKeyWrapper.WrappedKey(
                ciphertextB64: encryptedValue,
                ivB64: iv,
                macB64: mac
            )
            contentKey = try ContentKeyWrapper.unwrap(wrapped, wrappingKey: transportKey, info: Self.infoUserWrap)
        } catch {
            return failClosed("Content key unwrap failed: \(error)")
        }

        // ---- 5. Parse encryption.xml ----
        guard let encryptionUrl = AnyURL(string: "META-INF/encryption.xml") else {
            return failClosed("Could not build encryption.xml URL")
        }
        guard let encryptionResource = container[encryptionUrl] else {
            return failClosed("encryption.xml not present in container")
        }
        let encResult = await encryptionResource.read()
        let encryptionBytes: Data
        switch encResult {
        case .success(let data):
            encryptionBytes = data
        case .failure:
            return failClosed("Could not read META-INF/encryption.xml")
        }

        let encryptedPaths = EncryptionXmlParser.parse(encryptionBytes)
        if encryptedPaths.isEmpty {
            logger.warning("License present but encryption.xml lists zero resources — opening as plaintext")
        }

        // ---- 6. Wrap container ----
        let wrappedContainer = InkyomiDecryptingContainer(
            source: container,
            contentKey: contentKey,
            encryptedPaths: encryptedPaths
        )
        containerAsset.container = wrappedContainer
        // Must nil out sourceURL so Readium doesn't bypass the container and read raw ZIP
        let wrappedAsset = Asset.container(ContainerAsset(
            container: wrappedContainer,
            format: containerAsset.format
        ))

        debugLog("ContentProtection: SUCCESS - engaged for loanId=\(loanId) (\(encryptedPaths.count) encrypted resources), format=\(containerAsset.format)")
        logger.info("Inkyomi protection engaged for loanId=\(loanId) (\(encryptedPaths.count) encrypted resources)")
        return .success(ContentProtectionAsset(
            asset: wrappedAsset,
            onCreatePublication: { _, _, services in
                services.setContentProtectionServiceFactory { _ in
                    InkyomiContentProtectionService()
                }
            }
        ))
    }

    // MARK: - Helpers

    /// Returns just the loanId string (Sendable) to avoid crossing isolation boundaries with SwiftData models.
    @MainActor
    private static func findLoanId(derivedLoanId: String?, licenseId: String, modelContainer: ModelContainer) -> String? {
        let context = modelContainer.mainContext

        // Try by derived loan ID first
        if let loanId = derivedLoanId {
            let lid = loanId
            let descriptor = FetchDescriptor<LoanCacheModel>(
                predicate: #Predicate { $0.loanId == lid }
            )
            if let loan = try? context.fetch(descriptor).first {
                return loan.loanId
            }
        }

        // Fall back to licenseId
        let licId = licenseId
        let descriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate {
                $0.licenseId == licId && ($0.status == "active" || $0.status == "ready")
            }
        )
        return try? context.fetch(descriptor).first?.loanId
    }

    private func failClosed(_ message: String) -> Result<ContentProtectionAsset, ContentProtectionOpenError> {
        logger.error("Inkyomi fail-closed: \(message)")
        return .failure(.reading(.decoding(message)))
    }

    private func debugLog(_ msg: String) {
        let logFile = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reader_debug.log")
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    // MARK: - ContentProtectionService

    /// Tells Readium the publication is unlocked (decryption is handled
    /// transparently by InkyomiDecryptingContainer). Without this service
    /// registered, the navigator sees encryption.xml and refuses to render.
    private final class InkyomiContentProtectionService: ContentProtectionService {
        let scheme = ContentProtectionScheme.lcp
        let isRestricted = false
        let error: Error? = nil
        let rights: UserRights = UnrestrictedUserRights()
    }

    private func hexToBytes(_ hex: String) -> Data {
        precondition(hex.count % 2 == 0, "transport_secret hex must have even length")
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        for _ in 0..<hex.count / 2 {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                preconditionFailure("Invalid hex character")
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
