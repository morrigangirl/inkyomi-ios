import Foundation
import CryptoKit

/// Inkyomi bound-passphrase derivation — Swift mirror of the
/// `computeBoundPassphrase` primitive in `inkyomi-crypto/kdf.ts`.
///
/// Binds an account (email + PIN) to a per-device secret via HMAC-SHA256,
/// producing a stable passphrase that never leaves the device. Conformance
/// with the server is pinned by the shared `kdf.json` vectors exercised in
/// `InkyomiCryptoVectorTests`.
enum InkyomiKdf {
    /// Bound passphrase = HMAC-SHA256(deviceSecret, "email:pin"), email lowercased.
    static func computeBoundPassphrase(deviceSecret: Data, email: String, pin: String) -> Data {
        precondition(deviceSecret.count == 32, "device_secret must be 32 bytes")
        let key = SymmetricKey(data: deviceSecret)
        let message = Data("\(email.lowercased()):\(pin)".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(mac)
    }
}
