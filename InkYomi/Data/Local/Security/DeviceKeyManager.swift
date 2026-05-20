import Foundation
import Security
import CryptoKit

struct DeviceKeyManager {
    private static let keyTag = "shop.inkcolors.InkYomi.deviceKey.ec256"

    /// Generate or retrieve an EC P-256 key pair.
    /// Uses Secure Enclave on real devices, falls back to regular Keychain on simulator.
    static func ensureKeyPair() throws -> SecKey {
        // Try to retrieve existing key
        if let existing = try? getPrivateKey() {
            return existing
        }
        return try generateKeyPair()
    }

    /// Export the public key as PEM-encoded string for device registration.
    static func publicKeyPEM() throws -> String {
        let privateKey = try ensureKeyPair()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw DeviceKeyError.publicKeyExtractionFailed
        }
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw DeviceKeyError.publicKeyExportFailed
        }

        // Wrap in PEM format (X9.62 uncompressed point for P-256)
        let base64 = publicKeyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----"
    }

    // MARK: - Private

    private static func generateKeyPair() throws -> SecKey {
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as [String: Any],
        ]

        #if !targetEnvironment(simulator)
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        #endif

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw DeviceKeyError.keyGenerationFailed(error?.takeRetainedValue() as Error?)
        }
        return privateKey
    }

    private static func getPrivateKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecReturnRef as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            // Keychain returned `errSecSuccess` but we still defensively
            // type-check the result — a force cast here would crash the
            // auth path on the (rare) "successful but wrong type" path.
            guard let key = result, CFGetTypeID(key) == SecKeyGetTypeID() else {
                throw DeviceKeyError.keyRetrievalFailed(errSecInvalidKeyRef)
            }
            return (key as! SecKey)  // safe: type checked above
        case errSecItemNotFound:
            return nil
        default:
            throw DeviceKeyError.keyRetrievalFailed(status)
        }
    }
}

enum DeviceKeyError: Error {
    case keyGenerationFailed(Error?)
    case keyRetrievalFailed(OSStatus)
    case publicKeyExtractionFailed
    case publicKeyExportFailed
}
