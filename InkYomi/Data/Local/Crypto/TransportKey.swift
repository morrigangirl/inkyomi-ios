import Foundation
import CryptoKit

/// Transport key derivation — Swift mirror of `inkyomi-crypto/transport-key.ts`.
///
/// transport_key = HMAC-SHA256(transport_secret, license_id + ":inkyomi/v1/transport")
enum TransportKey {
    static let info = "inkyomi/v1/transport"

    static func derive(transportSecret: Data, licenseId: String) -> Data {
        precondition(transportSecret.count == 32, "transport_secret must be 32 bytes")
        let key = SymmetricKey(data: transportSecret)
        let message = Data("\(licenseId):\(info)".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(mac)
    }
}
