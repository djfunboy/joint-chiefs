import Foundation
import JointChiefsCore

// The single binary that touches Joint Chiefs' credential file. Every other
// component (CLI, MCP server, setup app) invokes this via Process and reads the
// key from stdout. Keeping one accessor means the file's read/write path is
// auditable in exactly one place.
//
// As of v0.5.7 the backing store is `CredentialStore` — a 0600 JSON file at
// ~/Library/Application Support/Joint Chiefs/credentials.json. This replaced the
// macOS Keychain, whose GUI access prompt could not be answered by headless
// CLI/MCP sessions (SSH, cron, no logged-in user). A file read has no session
// or prompt dependency.
//
// The `migrate` subcommand moves keys left behind in the legacy Keychain
// (v0.5.6 and earlier) into the file store; the setup app runs it once at
// launch.
//
// Output contract:
//   read:    raw key bytes on stdout, NO trailing newline
//   write:   confirmation on stdout, key echo suppressed
//   delete:  confirmation on stdout
//   migrate: summary line on stdout
//   errors:  diagnostic line on stderr, non-zero exit
//
// Exit codes (stable — scripts and callers depend on these):
//   0  success
//   2  credential-file failure (unreadable, corrupt, write error)
//   3  item not found (read only)
//   4  legacy: keychain prompt required but interaction disabled (unused by the
//      file store; retained so older callers still map the code)
//   5  other error
//   6  legacy key found in the old Keychain — needs migration (read only)
//   64 usage error

enum ExitCode: Int32 {
    case success = 0
    case credentialFailure = 2
    case itemNotFound = 3
    case interactionNotAllowed = 4
    case otherError = 5
    case legacyNeedsMigration = 6
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
          jointchiefs-keygetter migrate
        """, .usage)
}

/// Provider accounts the `migrate` subcommand sweeps out of the legacy Keychain.
let migratableAccounts = ["openai", "anthropic", "gemini", "grok"]

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }

switch cmd {
case "read":
    guard args.count == 2 else { usage() }
    let account = args[1]
    do {
        let key = try CredentialStore.retrieve(for: account)
        FileHandle.standardOutput.write(Data(key.utf8))
        exit(ExitCode.success.rawValue)
    } catch CredentialStoreError.itemNotFound {
        // No key in the file store. Before reporting "not found", probe the
        // legacy Keychain — prompt-free, metadata only. A legacy item means the
        // user upgraded from v0.5.6 without migrating; signal exit 6 so callers
        // can point them at the setup app.
        if LegacyKeychainStore.exists(for: account) {
            die("legacy key for '\(account)' needs migration — open the Joint Chiefs app once", .legacyNeedsMigration)
        }
        die("item not found: \(account)", .itemNotFound)
    } catch {
        die("read failed: \(error.localizedDescription)", .credentialFailure)
    }

case "write":
    guard args.count == 3 else { usage() }
    let account = args[1]
    let key = args[2]
    do {
        try CredentialStore.store(apiKey: key, for: account)
        print("[keygetter] wrote \(account)")
        exit(ExitCode.success.rawValue)
    } catch {
        die("write failed: \(error.localizedDescription)", .credentialFailure)
    }

case "delete":
    guard args.count == 2 else { usage() }
    let account = args[1]
    do {
        try CredentialStore.delete(for: account)
        print("[keygetter] deleted \(account)")
        exit(ExitCode.success.rawValue)
    } catch {
        die("delete failed: \(error.localizedDescription)", .credentialFailure)
    }

case "migrate":
    guard args.count == 1 else { usage() }
    var migrated: [String] = []
    var alreadyPresent = 0
    for account in migratableAccounts {
        // Already in the file store — nothing to do.
        if CredentialStore.accountExists(account) {
            alreadyPresent += 1
            continue
        }
        // Read the legacy item. This is the one operation that can surface a
        // macOS access prompt — acceptable because `migrate` runs from the
        // setup app while the user is present. A dismissed or failed read for
        // one account is logged and skipped, never fatal.
        let legacyKey: String
        do {
            legacyKey = try LegacyKeychainStore.retrieve(for: account)
        } catch KeychainError.itemNotFound {
            continue
        } catch {
            FileHandle.standardError.write(Data(
                "[keygetter] migrate: skipped \(account) — \(error.localizedDescription)\n".utf8))
            continue
        }
        // Write to the file store and verify the round-trip BEFORE deleting the
        // legacy item — never destroy the only copy of a key.
        do {
            try CredentialStore.store(apiKey: legacyKey, for: account)
            let verify = try CredentialStore.retrieve(for: account)
            guard verify == legacyKey else {
                FileHandle.standardError.write(Data(
                    "[keygetter] migrate: verify mismatch for \(account) — legacy item kept\n".utf8))
                continue
            }
        } catch {
            FileHandle.standardError.write(Data(
                "[keygetter] migrate: write failed for \(account) — \(error.localizedDescription); legacy item kept\n".utf8))
            continue
        }
        try? LegacyKeychainStore.delete(for: account)
        migrated.append(account)
    }
    let movedList = migrated.isEmpty ? "none" : migrated.joined(separator: ", ")
    print("[keygetter] migrate: moved \(migrated.count) (\(movedList)), \(alreadyPresent) already in file store")
    exit(ExitCode.success.rawValue)

default:
    usage()
}
