import Foundation

/// Per-loan hashed passphrase persistence in Keychain.
struct LcpPassphraseManager {
    private let keychain: KeychainManager

    init(keychain: KeychainManager = KeychainManager(service: Constants.Keychain.passphraseService)) {
        self.keychain = keychain
    }

    func getHashedPassphrase(_ loanId: String) -> String? {
        try? keychain.readString(forKey: loanId)
    }

    func storeHashedPassphrase(_ hash: String, loanId: String) throws {
        try keychain.save(hash, forKey: loanId)
    }

    func deletePassphrase(loanId: String) throws {
        try keychain.delete(forKey: loanId)
    }
}
