import Foundation

/// Per-loan transport secret persistence in Keychain.
struct LcpTransportSecretStore {
    private let keychain: KeychainManager

    init(keychain: KeychainManager = KeychainManager(service: Constants.Keychain.transportService)) {
        self.keychain = keychain
    }

    func getTransportSecretHex(_ loanId: String) -> String? {
        try? keychain.readString(forKey: loanId)
    }

    func storeTransportSecretHex(_ hex: String, loanId: String) throws {
        try keychain.save(hex, forKey: loanId)
    }

    func deleteTransportSecret(loanId: String) throws {
        try keychain.delete(forKey: loanId)
    }
}
