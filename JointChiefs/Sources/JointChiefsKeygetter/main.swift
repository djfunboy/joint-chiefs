import Foundation
import JointChiefsCore

// The single binary permitted to touch Joint Chiefs' Keychain items. Every other
// component (CLI, MCP server, setup app) invokes this via Process and reads the
// key from stdout. The macOS Keychain ACL trusts exactly one signed identity
// (com.jointchiefs.keygetter), so there is no cross-binary sharing problem.
//
// Validated empirically in prototypes/keychain-access: writes from the app flow,
// reads from the CLI context and from headless MCP invocations — all silent, no
// dialogs, survives binary replacement on update.
//
// Output contract:
//   read:   raw key bytes on stdout, NO trailing newline
//   write:  confirmation on stdout, key echo suppressed
//   delete: confirmation on stdout
//   errors: diagnostic line on stderr, non-zero exit
//
// Exit codes (stable — scripts and callers depend on these):
//   0  success
//   2  keychain failure (unexpected status, encode/decode)
//   3  item not found (read only)
//   4  keychain prompt required but interaction disabled (headless-failure case)
//   5  other keychain error
//   64 usage error

enum ExitCode: Int32 {
    case success = 0
    case keychainFailure = 2
    case itemNotFound = 3
    case interactionNotAllowed = 4
    case otherKeychain = 5
    case usage = 64
}

func die(_ message: String, _ code: ExitCode) -> Never {
    FileHandle.standardError.write(Data("[keygetter] \(message)\n".utf8))
    exit(code.rawValue)
}

func usage() -> Never {
    die("""
        usage:
          jointchiefs-keygetter write <account> <key>
          jointchiefs-keygetter read <account>
          jointchiefs-keygetter delete <account>
        """, .usage)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }

switch cmd {
case "read":
    guard args.count == 2 else { usage() }
    let account = args[1]
    do {
        let key = try KeychainService.retrieve(for: account)
        FileHandle.standardOutput.write(Data(key.utf8))
        exit(ExitCode.success.rawValue)
    } catch KeychainError.itemNotFound {
        die("item not found: \(account)", .itemNotFound)
    } catch KeychainError.unexpectedStatus(let status) where status == errSecInteractionNotAllowed {
        die("keychain prompt required but interaction not allowed (headless)", .interactionNotAllowed)
    } catch KeychainError.unexpectedStatus(let status) {
        die("keychain status \(status)", .otherKeychain)
    } catch {
        die("keychain failure: \(error.localizedDescription)", .keychainFailure)
    }

case "write":
    guard args.count == 3 else { usage() }
    let account = args[1]
    let key = args[2]
    do {
        try KeychainService.store(apiKey: key, for: account)
        print("[keygetter] wrote \(account)")
        exit(ExitCode.success.rawValue)
    } catch {
        die("write failed: \(error.localizedDescription)", .keychainFailure)
    }

case "delete":
    guard args.count == 2 else { usage() }
    let account = args[1]
    do {
        try KeychainService.delete(for: account)
        print("[keygetter] deleted \(account)")
        exit(ExitCode.success.rawValue)
    } catch {
        die("delete failed: \(error.localizedDescription)", .keychainFailure)
    }

default:
    usage()
}
