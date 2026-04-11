import Foundation
import Security

/// Verifies an Inkyomi license document RSA-SHA256 signature.
///
/// The provider's RSA-2048 public certificate is shipped at
/// `Resources/inkyomi-provider-cert.pem` and parsed via `parsePublicKey`.
enum LicenseSignatureVerifier {

    /// Verify `signatureB64` against `document` using a `SecKey`.
    static func verify(jsonData: Data, signatureB64: String, publicKey: SecKey) -> Bool {
        guard let sigData = Data(base64Encoded: signatureB64) else { return false }

        let message: Data
        do {
            message = try CanonicalJSON.canonicalizeForSignature(jsonData: jsonData)
        } catch {
            return false
        }

        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            sigData as CFData,
            &error
        )
        return result
    }

    /// Verify using a parsed dictionary.
    static func verify(document: [String: Any], signatureB64: String, publicKey: SecKey) -> Bool {
        guard let sigData = Data(base64Encoded: signatureB64) else { return false }

        let message = CanonicalJSON.canonicalizeForSignature(document)

        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            sigData as CFData,
            &error
        )
    }

    /// Parse a PEM blob — accepts `BEGIN CERTIFICATE` (X.509) or `BEGIN PUBLIC KEY`.
    static func parsePublicKey(pem: String) throws -> SecKey {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("BEGIN CERTIFICATE") {
            let der = try decodePemBody(trimmed, label: "CERTIFICATE")
            guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
                throw SignatureVerifierError.invalidCertificate
            }
            guard let publicKey = SecCertificateCopyKey(certificate) else {
                throw SignatureVerifierError.publicKeyExtractionFailed
            }
            return publicKey
        } else {
            let der = try decodePemBody(trimmed, label: "PUBLIC KEY")
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            ]
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
                throw SignatureVerifierError.invalidPublicKey(error?.takeRetainedValue())
            }
            return key
        }
    }

    private static func decodePemBody(_ pem: String, label: String) throws -> Data {
        let beginMarker = "-----BEGIN \(label)-----"
        let endMarker = "-----END \(label)-----"

        guard let beginRange = pem.range(of: beginMarker),
              let endRange = pem.range(of: endMarker),
              beginRange.upperBound < endRange.lowerBound else {
            throw SignatureVerifierError.malformedPEM(label)
        }

        let body = pem[beginRange.upperBound..<endRange.lowerBound]
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)

        guard let data = Data(base64Encoded: body) else {
            throw SignatureVerifierError.base64DecodeFailed
        }
        return data
    }
}

enum SignatureVerifierError: Error {
    case malformedPEM(String)
    case base64DecodeFailed
    case invalidCertificate
    case publicKeyExtractionFailed
    case invalidPublicKey(CFError?)
}
