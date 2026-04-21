import Foundation
import Security

// Writes a test API key to the shared Keychain access group.
// Signed with Developer ID + keychain-access-groups entitlement matching TEAMID.com.jointchiefs.shared.

let service = "com.jointchiefs.prototype"
let account = "test-provider"
let testKey = "sk-prototype-12345-do-not-use"

let data = testKey.data(using: .utf8)!

// Legacy file-based Keychain (no entitlement needed). This mirrors the existing
// KeychainService in the main codebase — the question is whether another binary
// signed by the same Team ID can read these items silently.
let searchQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
]
SecItemDelete(searchQuery as CFDictionary)

let addQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    kSecValueData as String: data,
]

let status = SecItemAdd(addQuery as CFDictionary, nil)
if status == errSecSuccess {
    print("[writer] wrote test key to keychain (access group: VJMJQKCRMC.com.jointchiefs.shared)")
    exit(0)
} else {
    FileHandle.standardError.write(Data("[writer] SecItemAdd failed: \(status)\n".utf8))
    exit(1)
}
