import Foundation
import CommonCrypto
import CryptoKit

/// Content key wrap/unwrap — Swift mirror of `inkyomi-crypto/content-key.ts`.
///
/// Wraps a 32-byte content key with AES-256-CBC and HKDF-derived HMAC-SHA256.
/// The `info` string binds wraps to their purpose:
///   "inkyomi/v1/kek-wrap"   KEK → CK storage (server-side only)
///   "inkyomi/v1/user-wrap"  UserKey → CK transport (in license JSON)
enum ContentKeyWrapper {

    private static let keyBytes = 32
    private static let ivBytes = 16

    struct WrappedKey {
        let ciphertextB64: String
        let ivB64: String
        let macB64: String
    }

    enum WrapperError: Error {
        case macVerificationFailed
        case unexpectedPlaintextLength(Int)
        case decryptionFailed
        case blobTooShort
    }

    static func unwrap(_ wrapped: WrappedKey, wrappingKey: Data, info: String) throws -> Data {
        precondition(wrappingKey.count == keyBytes, "wrappingKey must be 32 bytes")

        guard let iv = Data(base64Encoded: wrapped.ivB64),
              let ct = Data(base64Encoded: wrapped.ciphertextB64),
              let expected = Data(base64Encoded: wrapped.macB64) else {
            throw WrapperError.macVerificationFailed
        }

        // Verify MAC (constant-time)
        let macKey = deriveMacKey(wrappingKey, info: info)
        let actual = hmacSHA256(key: macKey, message: iv + ct)
        guard constantTimeEqual(expected, actual) else {
            throw WrapperError.macVerificationFailed
        }

        // AES-256-CBC decrypt
        let plain = try aesCBCDecrypt(data: ct, key: wrappingKey, iv: iv)
        guard plain.count == keyBytes else {
            throw WrapperError.unexpectedPlaintextLength(plain.count)
        }
        return plain
    }

    /// Decrypt a single resource produced by the server's `encryptResource`.
    /// Format: first 16 bytes = IV, rest = AES-256-CBC ciphertext.
    static func decryptResource(_ blob: Data, contentKey: Data) throws -> Data {
        precondition(contentKey.count == keyBytes, "contentKey must be 32 bytes")
        guard blob.count >= ivBytes else {
            throw WrapperError.blobTooShort
        }
        let iv = blob.prefix(ivBytes)
        let ct = blob.dropFirst(ivBytes)
        return try aesCBCDecrypt(data: Data(ct), key: contentKey, iv: Data(iv))
    }

    // MARK: - Private

    /// HKDF-Expand single block: HMAC(key, info || 0x01)
    private static func deriveMacKey(_ aesKey: Data, info: String) -> Data {
        var infoBytes = Data(info.utf8)
        infoBytes.append(0x01)
        return hmacSHA256(key: aesKey, message: infoBytes)
    }

    private static func hmacSHA256(key: Data, message: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey)
        return Data(mac)
    }

    private static func aesCBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        var outputLength = data.count + kCCBlockSizeAES128
        var output = Data(count: outputLength)

        let status = output.withUnsafeMutableBytes { outputPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            outputPtr.baseAddress, outputPtr.count,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw WrapperError.decryptionFailed
        }
        output.count = outputLength
        return output
    }

    /// Constant-time comparison to prevent timing side-channels on MAC verification.
    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[a.startIndex + i] ^ b[b.startIndex + i]
        }
        return result == 0
    }
}
