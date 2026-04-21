import Foundation
import Security

// Reads the test API key from the shared Keychain access group.
// Used to simulate both the CLI and the MCP-server reader contexts.

let service = "com.jointchiefs.prototype"
let account = "test-provider"

let role = CommandLine.arguments.dropFirst().first ?? "unknown"

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
]

var result: AnyObject?
let status = SecItemCopyMatching(query as CFDictionary, &result)

switch status {
case errSecSuccess:
    if let data = result as? Data, let key = String(data: data, encoding: .utf8) {
        // Print only a redacted prefix — don't leak keys even in test output
        let prefix = String(key.prefix(8))
        print("[reader:\(role)] success — read key prefix: \(prefix)…")
        exit(0)
    } else {
        FileHandle.standardError.write(Data("[reader:\(role)] decoded non-string data\n".utf8))
        exit(2)
    }
case errSecItemNotFound:
    FileHandle.standardError.write(Data("[reader:\(role)] item not found\n".utf8))
    exit(3)
case errSecInteractionNotAllowed:
    FileHandle.standardError.write(Data("[reader:\(role)] FATAL — Keychain prompt required but interaction not allowed (this is the headless-MCP failure case)\n".utf8))
    exit(4)
default:
    FileHandle.standardError.write(Data("[reader:\(role)] SecItemCopyMatching failed: \(status)\n".utf8))
    exit(5)
}
