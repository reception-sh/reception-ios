import Foundation
import Security

internal enum KeychainStore {
    /// `unavailable` (for example before the first unlock) must never be treated as "no item".
    enum ReadResult: Equatable { case value(String), missing, unavailable }

    static func read(account: String) -> ReadResult {
        var query = query(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            Log.error("Secure storage read failed, OSStatus \(status)")
            return .unavailable
        }
        return .value(value)
    }

    /// Items stay on this device and remain readable in the background after the first unlock.
    static func save(_ value: String, account: String) -> Bool {
        let attributes: [CFString: Any] = [kSecValueData: Data(value.utf8),
                                         kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else {
            Log.error("Secure storage update failed, OSStatus \(status)")
            return false
        }
        let added = SecItemAdd(query(account).merging(attributes) { _, new in new } as CFDictionary, nil)
        if added != errSecSuccess { Log.error("Secure storage add failed, OSStatus \(added)") }
        return added == errSecSuccess
    }

    static func delete(account: String) -> Bool {
        let status = SecItemDelete(query(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.reception.sdk", kSecAttrAccount: account]
    }
}
