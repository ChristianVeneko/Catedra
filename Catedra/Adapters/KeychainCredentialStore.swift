import Foundation
import Security

/// Stores the SAIA username and password as two generic-password items under one service.
struct KeychainCredentialStore: CredentialStoring {
    static let defaultService = "com.cmendoza.catedra.saia"
    private let service: String
    private let usernameAccount = "username"
    private let passwordAccount = "password"

    init(service: String = KeychainCredentialStore.defaultService) { self.service = service }

    func load() -> SAIACredentials? {
        guard let user = read(usernameAccount), let pass = read(passwordAccount) else { return nil }
        return SAIACredentials(username: user, password: pass)
    }

    func save(_ credentials: SAIACredentials) throws {
        try write(usernameAccount, credentials.username)
        try write(passwordAccount, credentials.password)
    }

    func delete() throws {
        for account in [usernameAccount, passwordAccount] {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        }
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ account: String, _ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: Error, LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Error del llavero (código \(status))." }
}
