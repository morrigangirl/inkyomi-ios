import Foundation
import Security

/// Loads the Inkyomi provider's signing public key from the app bundle.
///
/// The PEM file at `Resources/inkyomi-provider-cert.pem` is the RSA-2048
/// public key used to verify license signatures. Shipping it with the binary
/// means the client never has to trust a network fetch.
final class ProviderCertStore: @unchecked Sendable {
    static let shared = ProviderCertStore()

    private var cached: SecKey?
    private let lock = NSLock()

    func publicKey() throws -> SecKey {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }

        guard let url = Bundle.main.url(forResource: Constants.DRM.providerCertFilename, withExtension: "pem"),
              let pem = try? String(contentsOf: url, encoding: .utf8) else {
            throw ProviderCertError.certNotFound
        }

        let key = try LicenseSignatureVerifier.parsePublicKey(pem: pem)
        cached = key
        return key
    }
}

enum ProviderCertError: Error {
    case certNotFound
}
