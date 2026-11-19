import Foundation
import Security

/// The person's AI keys, one per service, in their login Keychain. Never in settings, which are plain JSON on disk,
/// never logged, and never sent back to Ledge.
enum Keychain {
    private static let service = "app.ledge.launcher.ai"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    /// Whether a key is saved, read without the key itself so macOS doesn't ask for access.
    static func has(_ account: String) -> Bool {
        var attributes = query(account)
        attributes[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func key(_ account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String, for account: String) -> Bool {
        let data = Data(key.utf8)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query(account) as CFDictionary, update as CFDictionary) == errSecSuccess { return true }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Ledge Launcher AI key"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
