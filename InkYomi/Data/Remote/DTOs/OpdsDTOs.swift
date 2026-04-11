import Foundation

struct LcpLicenseDocument: Codable, Sendable {
    let id: String
    let issued: String?
    let provider: String?
    let encryption: LcpEncryption
    let links: [LcpLink]
    let signature: LcpSignature?
}

struct LcpEncryption: Codable, Sendable {
    let profile: String?
    let contentKey: LcpContentKey
}

struct LcpContentKey: Codable, Sendable {
    let algorithm: String?
    let encryptedValue: String?
    let iv: String?
    let mac: String?
}

struct LcpLink: Codable, Sendable {
    let rel: String
    let href: String
    let type: String?
}

struct LcpSignature: Codable, Sendable {
    let algorithm: String?
    let value: String?
    let certificate: String?
}

struct LsdStatusDocument: Codable, Sendable {
    let id: String
    let status: String
    let message: String?
    let updated: LsdUpdated?
    let links: [LcpLink]?
}

struct LsdUpdated: Codable, Sendable {
    let license: String?
    let status: String?
}

struct BorrowResponse: Decodable {
    let license: LcpLicenseDocument
    let transportSecretHex: String
}

struct TransportSecretResponse: Decodable {
    let transportSecretHex: String
}
