import Foundation
import Security

/// Provides secure storage for provider API keys using the macOS Keychain.
///
/// Security model:
/// - Items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — keys are device-local
///   and excluded from backups/iCloud migration.
/// - No biometric/user-presence gating — appropriate for frequently-accessed API keys.
/// - Swift String values remain in memory until deallocated (platform limitation).
public enum KeychainService {

    static let service = "com.jointchiefs.provider"

    // MARK: - Public Methods

    /// Stores an API key in the keychain for the given account.
    ///
    /// If an entry already exists, it is deleted and re-created to ensure the
    /// accessibility class is enforced (SecItemUpdate cannot change it).
    ///
    /// - Parameters:
    ///   - apiKey: The API key string to store.
    ///   - account: The provider account identifier (e.g., "openai", "gemini").
    /// - Throws: `KeychainError.encodingFailed` if the key cannot be encoded,
    ///           or `KeychainError.unexpectedStatus` for other Keychain failures.
    public static func store(apiKey: String, for account: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        // Delete any existing item first — ensures the accessibility class is applied
        // even to pre-existing items (SecItemUpdate cannot change kSecAttrAccessible).
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(searchQuery as CFDictionary)

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieves an API key from the keychain for the given account.
    ///
    /// - Parameter account: The provider account identifier.
    /// - Returns: The stored API key string.
    /// - Throws: `KeychainError.itemNotFound` if no entry exists,
    ///           `KeychainError.encodingFailed` if the stored data cannot be decoded,
    ///           or `KeychainError.unexpectedStatus` for other Keychain failures.
    public static func retrieve(for account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let apiKey = String(data: data, encoding: .utf8) else {
                throw KeychainError.encodingFailed
            }
            return apiKey
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Deletes an API key from the keychain for the given account.
    ///
    /// Does not throw if the item does not exist.
    ///
    /// - Parameter account: The provider account identifier.
    /// - Throws: `KeychainError.unexpectedStatus` if deletion fails for a reason
    ///           other than the item not existing.
    public static func delete(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
