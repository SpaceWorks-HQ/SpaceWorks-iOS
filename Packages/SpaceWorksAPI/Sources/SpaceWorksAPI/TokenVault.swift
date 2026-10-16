import Foundation
import Security
import CryptoKit

/// One Keychain value contains the whole pair; updating it is atomic. Nothing is stored in defaults.
public protocol TokenStorage: Sendable {
    func load() throws -> TokenPair?
    func store(_ pair: TokenPair?) throws
}

public struct TokenVault: TokenStorage {
    private let account: String
    private let service: String
    public init(origin: ServerOrigin, service: String = "org.spaceworks.device-session") {
        account = SHA256.hash(data: Data(origin.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        self.service = service
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    public func load() throws -> TokenPair? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw vaultError }
        return try JSONDecoder().decode(TokenPair.self, from: data)
    }
    public func store(_ pair: TokenPair?) throws {
        guard let pair else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        let value = try JSONEncoder().encode(pair)
        let changes: [String: Any] = [kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query.merging(changes) { _, new in new } as CFDictionary, nil))
        } else { try check(status) }
    }
    private var vaultError: APIError {
        APIError(status: 0, code: "secure_storage_unavailable", detail: "Secure storage is unavailable. Unlock your device and try again.")
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw vaultError }
    }
}
