import CryptoKit
import Foundation
import Security
import SpaceWorksAPI

/// Local Keychain metadata, never an API payload. A raw APNs token is never persisted here.
struct PushStoredRegistration: Codable, Equatable, Sendable {
    let makerspaceID: Int
    let deviceID: Int
    let tokenDigest: String
    let environment: String
    var pendingDeletion: Bool = false
}
struct PushRegistrationSnapshot: Codable, Equatable, Sendable {
    var enabled = false
    var registrations: [PushStoredRegistration] = []
}
protocol PushRegistrationStorage: Sendable {
    func load() throws -> PushRegistrationSnapshot
    func store(_ snapshot: PushRegistrationSnapshot) throws
}

struct PushRegistrationVault: PushRegistrationStorage {
    private let account: String
    private let service: String
    init(origin: ServerOrigin, accountID: Int, service: String = (Bundle.main.bundleIdentifier ?? "org.spaceworks.app") + ".push-registrations") {
        account = Self.digest(origin.url.absoluteString + ".account.\(accountID)")
        self.service = service
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    func load() throws -> PushRegistrationSnapshot {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return PushRegistrationSnapshot() }
        try check(status)
        guard let data = result as? Data, data.count <= 1_048_576 else { throw storageError }
        let snapshot = try JSONDecoder().decode(PushRegistrationSnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }
    func store(_ snapshot: PushRegistrationSnapshot) throws {
        try validate(snapshot)
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 1_048_576 else { throw storageError }
        let changes: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound { try check(SecItemAdd(query.merging(changes) { _, new in new } as CFDictionary, nil)) }
        else { try check(status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func validate(_ value: PushRegistrationSnapshot) throws {
        var keys = Set<Int>()
        guard value.registrations.allSatisfy({ row in
            row.makerspaceID > 0 && row.deviceID > 0 && keys.insert(row.makerspaceID).inserted &&
            ["development", "production"].contains(row.environment) && row.tokenDigest.count == 64 &&
            row.tokenDigest.allSatisfy { "0123456789abcdef".contains($0) }
        }) else { throw storageError }
    }
    private var storageError: APIError { APIError(status: 0, code: "push_storage_unavailable", detail: "Notification settings could not be stored securely. Unlock your device and try again.") }
    private func check(_ status: OSStatus) throws { guard status == errSecSuccess else { throw storageError } }
    static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}
