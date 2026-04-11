import Foundation
import CryptoKit

/// Inkyomi v1 KDF — Swift mirror of `inkyomi-crypto/kdf.ts`.
///
/// Argon2id parameters (MUST match server):
///   memory     = 64 MiB
///   iterations = 3
///   parallelism = 4
///   tag length = 32 bytes
///   salt length = 16 bytes
///
/// Note: Argon2id requires a C-bridged library (swift-argon2 or libargon2).
/// The `deriveUserKey` function is a placeholder until the Argon2 dependency
/// is integrated. The `computeBoundPassphrase` function uses HMAC-SHA256
/// and works immediately.
enum InkyomiKdf {
    static let version = 1
    static let saltBytes = 16
    static let keyBytes = 32
    static let memoryKiB = 64 * 1024
    static let iterations = 3
    static let parallelism = 4

    static func generateSalt() -> Data {
        var salt = Data(count: saltBytes)
        salt.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes, ptr.baseAddress!)
        }
        return salt
    }

    /// Derive a 32-byte User Key from passphrase and salt via Argon2id.
    /// Requires Argon2 library integration — will be implemented in Phase 6 detail.
    static func deriveUserKey(passphrase: Data, salt: Data) -> Data {
        precondition(salt.count == saltBytes, "salt must be \(saltBytes) bytes")
        // TODO: Integrate swift-argon2 or libargon2 C bridge
        // For now, return a placeholder that will fail tests until the dependency is added.
        fatalError("Argon2id not yet integrated — requires C library bridge")
    }

    /// Bound passphrase = HMAC-SHA256(deviceSecret, "email:pin")
    static func computeBoundPassphrase(deviceSecret: Data, email: String, pin: String) -> Data {
        precondition(deviceSecret.count == 32, "device_secret must be 32 bytes")
        let key = SymmetricKey(data: deviceSecret)
        let message = Data("\(email.lowercased()):\(pin)".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(mac)
    }
}
