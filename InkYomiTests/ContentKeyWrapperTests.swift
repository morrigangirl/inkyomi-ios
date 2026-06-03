import XCTest
import CommonCrypto
import CryptoKit
@testable import InkYomi

/// Exercises `ContentKeyWrapper.unwrap` / `decryptResource` — the iOS half
/// of the Inkyomi content-key transport. The server owns the wrap side
/// (`inkyomi-crypto/content-key.ts`), so there is no shared fixed vector
/// for unwrap; instead these tests reconstruct the exact server wrap format
/// (AES-256-CBC + HKDF-Expand(HMAC-SHA256) MAC over IV‖ciphertext) from
/// fixed inputs and assert the production unwrap path recovers the original
/// key and rejects tampering — mirroring the backend's content-key tests.
final class ContentKeyWrapperTests: XCTestCase {

    // Fixed, deterministic inputs (not secret — test only).
    private let wrappingKey = Data(repeating: 0x2a, count: 32)
    private let contentKey = Data(repeating: 0x7c, count: 32)
    private let iv = Data(repeating: 0x10, count: 16)
    private let info = "inkyomi/v1/user-wrap"

    // MARK: - Local wrap (mirror of the server algorithm)

    /// HKDF-Expand single block, exactly as `ContentKeyWrapper.deriveMacKey`:
    /// HMAC(aesKey, info-bytes ‖ 0x01).
    private func deriveMacKey(_ aesKey: Data, info: String) -> Data {
        var infoBytes = Data(info.utf8)
        infoBytes.append(0x01)
        let mac = HMAC<SHA256>.authenticationCode(for: infoBytes, using: SymmetricKey(data: aesKey))
        return Data(mac)
    }

    private func hmacSHA256(key: Data, message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    private func aesCBCEncrypt(_ plaintext: Data, key: Data, iv: Data) -> Data {
        var outLength = plaintext.count + kCCBlockSizeAES128
        var out = Data(count: outLength)
        let status = out.withUnsafeMutableBytes { outPtr in
            plaintext.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, plaintext.count,
                            outPtr.baseAddress, outPtr.count,
                            &outLength
                        )
                    }
                }
            }
        }
        precondition(status == kCCSuccess, "test AES-CBC encrypt failed")
        out.count = outLength
        return out
    }

    /// Produce a `WrappedKey` for `key`, MAC-bound to `info`, exactly as the
    /// server would.
    private func wrap(_ key: Data, wrappingKey: Data, iv: Data, info: String) -> ContentKeyWrapper.WrappedKey {
        let ct = aesCBCEncrypt(key, key: wrappingKey, iv: iv)
        let macKey = deriveMacKey(wrappingKey, info: info)
        let mac = hmacSHA256(key: macKey, message: iv + ct)
        return ContentKeyWrapper.WrappedKey(
            ciphertextB64: ct.base64EncodedString(),
            ivB64: iv.base64EncodedString(),
            macB64: mac.base64EncodedString()
        )
    }

    // MARK: - unwrap

    func testUnwrapRoundTripsContentKey() throws {
        let wrapped = wrap(contentKey, wrappingKey: wrappingKey, iv: iv, info: info)
        let recovered = try ContentKeyWrapper.unwrap(wrapped, wrappingKey: wrappingKey, info: info)
        XCTAssertEqual(recovered, contentKey)
    }

    func testUnwrapRejectsTamperedCiphertext() throws {
        var wrapped = wrap(contentKey, wrappingKey: wrappingKey, iv: iv, info: info)
        // Flip one ciphertext byte; MAC must catch it.
        var ct = Data(base64Encoded: wrapped.ciphertextB64)!
        ct[0] ^= 0xFF
        wrapped = ContentKeyWrapper.WrappedKey(
            ciphertextB64: ct.base64EncodedString(),
            ivB64: wrapped.ivB64,
            macB64: wrapped.macB64
        )
        XCTAssertThrowsError(try ContentKeyWrapper.unwrap(wrapped, wrappingKey: wrappingKey, info: info)) { error in
            assertMacFailure(error)
        }
    }

    func testUnwrapRejectsWrongInfoBinding() throws {
        // Wrapped under user-wrap, but unwrap attempted with a different
        // purpose string — the MAC key differs, so it must fail.
        let wrapped = wrap(contentKey, wrappingKey: wrappingKey, iv: iv, info: info)
        XCTAssertThrowsError(
            try ContentKeyWrapper.unwrap(wrapped, wrappingKey: wrappingKey, info: "inkyomi/v1/kek-wrap")
        ) { error in
            assertMacFailure(error)
        }
    }

    func testUnwrapRejectsWrongWrappingKey() throws {
        let wrapped = wrap(contentKey, wrappingKey: wrappingKey, iv: iv, info: info)
        let wrongKey = Data(repeating: 0x99, count: 32)
        XCTAssertThrowsError(try ContentKeyWrapper.unwrap(wrapped, wrappingKey: wrongKey, info: info)) { error in
            // Wrong key fails MAC verification before any decrypt is attempted.
            assertMacFailure(error)
        }
    }

    func testUnwrapRejectsMalformedBase64() {
        let wrapped = ContentKeyWrapper.WrappedKey(
            ciphertextB64: "not base64!!!",
            ivB64: iv.base64EncodedString(),
            macB64: "AAAA"
        )
        XCTAssertThrowsError(try ContentKeyWrapper.unwrap(wrapped, wrappingKey: wrappingKey, info: info))
    }

    // MARK: - decryptResource

    func testDecryptResourceRoundTripsPayload() throws {
        let plaintext = Data("The quick brown fox jumps over the lazy dog. ".utf8)
        let resourceIv = Data((0..<16).map { UInt8($0) })
        // Server `encryptResource` format: IV ‖ AES-256-CBC(content_key).
        let blob = resourceIv + aesCBCEncrypt(plaintext, key: contentKey, iv: resourceIv)
        let decrypted = try ContentKeyWrapper.decryptResource(blob, contentKey: contentKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptResourceRejectsTooShortBlob() {
        let tooShort = Data(repeating: 0, count: 8) // < one IV
        XCTAssertThrowsError(try ContentKeyWrapper.decryptResource(tooShort, contentKey: contentKey)) { error in
            guard case ContentKeyWrapper.WrapperError.blobTooShort = error else {
                return XCTFail("expected .blobTooShort, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func assertMacFailure(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case ContentKeyWrapper.WrapperError.macVerificationFailed = error else {
            XCTFail("expected .macVerificationFailed, got \(error)", file: file, line: line)
            return
        }
    }
}
