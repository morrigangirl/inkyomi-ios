import XCTest
import Security
@testable import InkYomi

/// Cross-language crypto conformance tests.
///
/// These exercise the iOS crypto primitives against the SAME shared test
/// vectors the backend verifies in
/// `services/app-api/src/lib/inkyomi-crypto/__test-vectors__/`. The vector
/// JSON (and the dev signing key's public PEM) are bundled into this test
/// target under `Resources/inkyomi-crypto/`. Keeping both languages pinned
/// to identical vectors is what guarantees an iOS-unwrapped content key (or
/// a verified license signature) matches what the server produced.
final class InkyomiCryptoVectorTests: XCTestCase {

    // MARK: - Vector loading

    /// Load a bundled vector resource by name (+ extension) from the test
    /// bundle. Fails the test loudly if the resource isn't packaged.
    private func vectorData(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            XCTFail("Missing bundled vector resource \(name).\(ext)")
            throw VectorError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }

    private enum VectorError: Error { case missingResource(String) }

    /// Hex string → Data. Test-only helper (the production hex decoder is
    /// private), kept strict so a bad vector surfaces immediately.
    private func hex(_ string: String) -> Data {
        precondition(string.count % 2 == 0, "hex must be even length")
        var data = Data(capacity: string.count / 2)
        var idx = string.startIndex
        while idx < string.endIndex {
            let next = string.index(idx, offsetBy: 2)
            data.append(UInt8(string[idx..<next], radix: 16)!)
            idx = next
        }
        return data
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Canonical JSON

    func testCanonicalJSONVectors() throws {
        let data = try vectorData("canonical-json", "json")
        // Parse the vector file with JSONSerialization (NOT Codable): we
        // need the `input` sub-object as the native Foundation graph
        // (NSNumber / NSNull / NSDictionary) the canonicalizer consumes in
        // production. Going through Codable would coerce JSON `1` into
        // Bool, corrupting the inputs.
        guard let cases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return XCTFail("canonical-json vectors must be an array of objects")
        }
        XCTAssertFalse(cases.isEmpty, "canonical-json vectors should not be empty")

        for c in cases {
            let name = c["name"] as? String ?? "<unnamed>"
            guard let expected = c["expected"] as? String else {
                XCTFail("vector \"\(name)\" missing `expected`")
                continue
            }
            let input = c["input"]  // native Foundation value, may be nil only if absent
            let actual = CanonicalJSON.canonicalizeToString(input)
            XCTAssertEqual(actual, expected, "canonical JSON mismatch for case \"\(name)\"")
        }
    }

    // MARK: - Transport key derivation

    private struct TransportKeyVectors: Decodable {
        let info: String
        let vectors: [Vector]
        struct Vector: Decodable {
            let name: String
            let transportSecretHex: String
            let licenseId: String
            let expectedHex: String
        }
    }

    func testTransportKeyDerivationVectors() throws {
        let data = try vectorData("transport-key", "json")
        let parsed = try JSONDecoder().decode(TransportKeyVectors.self, from: data)

        // The Swift constant must match the vector's `info` string, since
        // the derived key binds it in.
        XCTAssertEqual(TransportKey.info, parsed.info)
        XCTAssertFalse(parsed.vectors.isEmpty)

        for v in parsed.vectors {
            let secret = hex(v.transportSecretHex)
            let derived = TransportKey.derive(transportSecret: secret, licenseId: v.licenseId)
            XCTAssertEqual(hexString(derived), v.expectedHex, "transport key mismatch for \"\(v.name)\"")
        }
    }

    // MARK: - KDF (bound passphrase)

    private struct KdfVectors: Decodable {
        let boundPassphrase: [BoundCase]
        struct BoundCase: Decodable {
            let name: String
            let deviceSecretHex: String
            let email: String
            let pin: String
            let expectedHex: String
        }
    }

    /// `computeBoundPassphrase` = HMAC-SHA256(device_secret, "email:pin")
    /// with the email lowercased. The shared `kdf.json` also carries Argon2id
    /// `deriveUserKey` vectors; the iOS app never used that derivation, so it
    /// isn't implemented here and those vectors are intentionally not exercised.
    func testBoundPassphraseVectors() throws {
        let data = try vectorData("kdf", "json")
        let parsed = try JSONDecoder().decode(KdfVectors.self, from: data)
        XCTAssertFalse(parsed.boundPassphrase.isEmpty)

        for c in parsed.boundPassphrase {
            let secret = hex(c.deviceSecretHex)
            let result = InkyomiKdf.computeBoundPassphrase(
                deviceSecret: secret,
                email: c.email,
                pin: c.pin
            )
            XCTAssertEqual(hexString(result), c.expectedHex, "bound passphrase mismatch for \"\(c.name)\"")
        }
    }

    /// Explicit guard for the case-folding behaviour the vectors assert:
    /// an uppercase email derives the SAME passphrase as its lowercase
    /// form (so a casing difference can't lock a reader out of a book).
    func testBoundPassphraseEmailIsCaseInsensitive() throws {
        let data = try vectorData("kdf", "json")
        let parsed = try JSONDecoder().decode(KdfVectors.self, from: data)

        let secret = hex("0101010101010101010101010101010101010101010101010101010101010101")
        let lower = InkyomiKdf.computeBoundPassphrase(deviceSecret: secret, email: "alice@example.com", pin: "1234")
        let upper = InkyomiKdf.computeBoundPassphrase(deviceSecret: secret, email: "ALICE@EXAMPLE.COM", pin: "1234")
        XCTAssertEqual(lower, upper)
        _ = parsed // touch to keep the vector file as the source of truth
    }

    // MARK: - RSA license signature verification

    private func devPublicKey() throws -> SecKey {
        let pem = try vectorData("dev-signing-key.pub", "pem")
        let pemString = String(decoding: pem, as: UTF8.self)
        return try LicenseSignatureVerifier.parsePublicKey(pem: pemString)
    }

    /// Load the license-signature vector via JSONSerialization (native
    /// Foundation types, so the `document` integers stay numeric).
    private func loadSignatureVector() throws -> (document: [String: Any], expectedCanonical: String, signatureB64: String) {
        let data = try vectorData("license-signature", "json")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let document = obj["document"] as? [String: Any],
              let expectedCanonical = obj["expectedCanonical"] as? String,
              let signatureB64 = obj["signatureB64"] as? String else {
            throw VectorError.missingResource("license-signature.json (malformed)")
        }
        return (document, expectedCanonical, signatureB64)
    }

    func testLicenseSignatureVerifies() throws {
        let vector = try loadSignatureVector()
        let publicKey = try devPublicKey()

        // Canonicalization of the document must match the vector exactly —
        // this is the message bytes the signature was computed over.
        let canonical = CanonicalJSON.canonicalizeForSignature(vector.document)
        XCTAssertEqual(String(decoding: canonical, as: UTF8.self), vector.expectedCanonical)

        // The real signature over that canonical form must verify, via both
        // the dictionary and the JSON-bytes verification entry points.
        XCTAssertTrue(
            LicenseSignatureVerifier.verify(document: vector.document, signatureB64: vector.signatureB64, publicKey: publicKey),
            "valid RSA-SHA256 signature should verify (document overload)"
        )

        let docData = try JSONSerialization.data(withJSONObject: vector.document)
        XCTAssertTrue(
            LicenseSignatureVerifier.verify(jsonData: docData, signatureB64: vector.signatureB64, publicKey: publicKey),
            "valid RSA-SHA256 signature should verify (jsonData overload)"
        )
    }

    func testTamperedDocumentFailsVerification() throws {
        let vector = try loadSignatureVector()
        let publicKey = try devPublicKey()

        // Flip a value in the document — the signature must no longer verify.
        var tampered = vector.document
        tampered["a"] = 2
        XCTAssertFalse(
            LicenseSignatureVerifier.verify(document: tampered, signatureB64: vector.signatureB64, publicKey: publicKey),
            "a tampered document must fail signature verification"
        )
    }

    func testGarbageSignatureFailsVerification() throws {
        let vector = try loadSignatureVector()
        let publicKey = try devPublicKey()

        XCTAssertFalse(
            LicenseSignatureVerifier.verify(document: vector.document, signatureB64: "not-base-64!!!", publicKey: publicKey),
            "non-base64 signature must be rejected, not crash"
        )
        // Valid base64 but wrong bytes.
        XCTAssertFalse(
            LicenseSignatureVerifier.verify(document: vector.document, signatureB64: "AAAA", publicKey: publicKey),
            "well-formed but incorrect signature must be rejected"
        )
    }
}
