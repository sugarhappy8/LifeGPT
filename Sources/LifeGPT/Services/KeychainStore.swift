import Foundation
import Security

/// Credentials are never written to preferences, save files, logs or exported transcripts.
enum KeychainStore {
    private static let service = "app.lifegpt.provider-credentials"
    static func read(_ account: String) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data else { throw KeyError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ secret: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        if secret.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError(status: status) }
            return
        }
        let updates = [kSecValueData as String: Data(secret.utf8)]
        let update = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = Data(secret.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeyError(status: status) }
        } else if update != errSecSuccess { throw KeyError(status: update) }
    }
    struct KeyError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unable to access credentials (\(status)).")" }
    }
}
