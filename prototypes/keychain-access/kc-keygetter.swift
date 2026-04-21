import Foundation
import Security

// Single-binary Keychain agent. Handles both writes and reads. This is the ONLY
// binary that touches the Keychain — everyone else (app, CLI, MCP) invokes this
// via Process to write or read keys. The Keychain ACL trusts exactly one identity
// (this binary's), so there is no cross-binary sharing problem.
//
// Usage:
//   jointchiefs-keygetter write <account> <key>
//   jointchiefs-keygetter read <account>
//   jointchiefs-keygetter delete <account>

let service = "com.jointchiefs.keygetter-prototype"

func die(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("[keygetter] \(msg)\n".utf8))
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    die("usage: keygetter <write|read|delete> <account> [<key>]", 64)
}

switch cmd {
case "write":
    guard args.count == 3 else { die("usage: keygetter write <account> <key>", 64) }
    let account = args[1]
    let key = args[2]

    let data = key.data(using: .utf8)!
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
        print("[keygetter] wrote \(account)")
        exit(0)
    } else {
        die("SecItemAdd failed: \(status)", 2)
    }

case "read":
    guard args.count == 2 else { die("usage: keygetter read <account>", 64) }
    let account = args[1]

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
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            die("decoded non-string data", 2)
        }
        // Keygetter contract: print raw key to stdout, caller reads and drops.
        // No trailing newline so calling code doesn't need to strip.
        FileHandle.standardOutput.write(Data(key.utf8))
        exit(0)
    case errSecItemNotFound:
        die("item not found", 3)
    case errSecInteractionNotAllowed:
        die("FATAL — Keychain prompt required (headless-MCP failure case)", 4)
    default:
        die("SecItemCopyMatching failed: \(status)", 5)
    }

case "delete":
    guard args.count == 2 else { die("usage: keygetter delete <account>", 64) }
    let account = args[1]
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        die("SecItemDelete failed: \(status)", 2)
    }
    print("[keygetter] deleted \(account)")
    exit(0)

default:
    die("unknown command: \(cmd)", 64)
}
