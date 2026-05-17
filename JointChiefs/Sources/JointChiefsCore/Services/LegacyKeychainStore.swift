import Foundation
import Security

/// Read-only access to API keys left in the macOS Keychain by Joint Chiefs
/// v0.5.6 and earlier.
///
/// As of v0.5.7 keys live in `CredentialStore` (a `0600` file) — the Keychain
/// proved unworkable for headless CLI/MCP use, where its GUI access prompt
/// cannot be answered. This type exists solely for the one-time migration path
/// (`jointchiefs-keygetter migrate`): it can detect and read legacy items so
/// they can be moved into the file store, then deleted. Nothing writes the
/// Keychain anymore.
public enum LegacyKeychainStore {

    static let service = "com.jointchiefs.keygetter"

    // MARK: - Public Methods

    /// Prompt-free existence probe for a legacy Keychain item.
    ///
    /// A metadata-only query (`kSecReturnData: false`) does not read the secret
    /// data, so it never triggers the macOS access prompt. Returns `false` on
    /// any failure (locked keychain, headless context) — best-effort, used only
    /// to decide whether to hint the user toward migration.
    ///
    /// - Parameter account: The provider account identifier.
    /// - Returns: `true` if a legacy item exists for this account.
    public static func exists(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    /// Retrieves a legacy API key from the Keychain for the given account.
    ///
    /// Reading the secret data can surface the macOS access prompt — this is
    /// only called from the migration path, which runs while the user is
    /// present in the setup app.
    ///
    /// - Parameter account: The provider account identifier.
    /// - Returns: The stored API key string.
    /// - Throws: `KeychainError.itemNotFound` if no entry exists,
    ///           `KeychainError.encodingFailed` if the stored data cannot be decoded,
    ///           or `KeychainError.unexpectedStatus` for other Keychain failures.
    public static func retrieve(for account: String) throws -> String {
        // Note: `kSecAttrAccessible` is deliberately absent. In a
        // `SecItemCopyMatching` query it acts as a match constraint, not an
        // attribute, and can cause spurious `errSecItemNotFound` against items
        // written with a different accessibility class.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    /// Deletes a legacy API key from the Keychain for the given account.
    ///
    /// Does not throw if the item does not exist. Called by the migration path
    /// only after the key has been written to `CredentialStore` and verified.
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
