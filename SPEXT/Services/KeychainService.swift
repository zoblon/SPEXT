import Foundation
import Security

/// Stores and reads the OpenAI API key securely in the macOS Keychain.
/// Much safer than UserDefaults/AppStorage, since the key is stored encrypted
/// in the Keychain store and not as plain text in a plist file.
struct KeychainService {

    /// Legacy service name from the TapTalk era. Intentionally kept
    /// so existing API keys are not lost after the rename to SPEXT.
    private static let service = "com.taptalk.apikey"
    private static let account = "openai"

    /// Reads the stored API key. Returns "" if none exists.
    static func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass           as String: kSecClassGenericPassword,
            kSecAttrService     as String: service,
            kSecAttrAccount     as String: account,
            kSecReturnData      as String: true,
            kSecMatchLimit      as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key  = String(data: data, encoding: .utf8)
        else { return "" }
        return key
    }

    /// Stores the API key in the Keychain. Overwrites an existing entry.
    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        let data = Data(key.utf8)

        // Update the existing entry
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return loadAPIKey() == key
        }

        guard updateStatus == errSecItemNotFound else { return false }

        // Create a new one
        var addQuery = query
        addQuery[kSecValueData as String] = data
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else { return false }
        return loadAPIKey() == key
    }

    /// Deletes the API key from the Keychain.
    @discardableResult
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
