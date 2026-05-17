import Foundation

/// Stores provider API keys in a permission-locked local file.
///
/// Default path: `~/Library/Application Support/Joint Chiefs/credentials.json`,
/// a flat JSON object `{ "openai": "sk-…", "anthropic": "…" }`. File mode is
/// `0600`, the parent directory `0700` — FileVault provides encryption at rest.
///
/// This replaces the macOS Keychain as the API-key store. The Keychain's
/// access approval is a GUI prompt that a headless CLI/MCP session (SSH, cron,
/// no logged-in user) cannot show or answer. A `0600` file has no session or
/// prompt dependency, so the CLI and MCP server read keys identically whether a
/// user is logged in or not. Mirrors `StrategyConfigStore` — same app-support
/// directory, same atomic write, same permission hardening.
public enum CredentialStore {

    // MARK: - Public API

    /// Store an API key for the given account, creating the file if needed.
    /// File mode is set to `0600`, the parent directory to `0700`.
    ///
    /// - Parameters:
    ///   - apiKey: The API key string to store.
    ///   - account: The provider account identifier (e.g., "openai", "gemini").
    ///   - url: Override the credentials-file location (tests only).
    /// - Throws: `CredentialStoreError.ioFailed` if the existing file is
    ///           corrupt or the write fails, `.encodingFailed` on encode error.
    public static func store(apiKey: String, for account: String, at url: URL? = nil) throws {
        let path = url ?? defaultURL
        // A missing file is a fresh start; a corrupt one must surface, not be
        // silently overwritten — that would discard every other stored key.
        var creds: [String: String] = [:]
        if FileManager.default.fileExists(atPath: path.path) {
            creds = try load(at: path)
        }
        creds[account] = apiKey
        try write(creds, to: path)
    }

    /// Retrieve an API key for the given account.
    ///
    /// - Returns: The stored API key string.
    /// - Throws: `CredentialStoreError.itemNotFound` if the file is absent or
    ///           the account has no key, `.ioFailed` if the file exists but
    ///           cannot be read or parsed. A missing key and a damaged file are
    ///           deliberately distinguishable.
    public static func retrieve(for account: String, at url: URL? = nil) throws -> String {
        let path = url ?? defaultURL
        let creds = try load(at: path)
        guard let key = creds[account] else {
            throw CredentialStoreError.itemNotFound
        }
        return key
    }

    /// Delete an API key for the given account. Does not throw if the file or
    /// the account is absent.
    public static func delete(for account: String, at url: URL? = nil) throws {
        let path = url ?? defaultURL
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        var creds = try load(at: path)
        guard creds[account] != nil else { return }
        creds.removeValue(forKey: account)
        try write(creds, to: path)
    }

    /// True when an account has a stored key. Never throws — a missing or
    /// corrupt file simply reports `false`.
    public static func accountExists(_ account: String, at url: URL? = nil) -> Bool {
        let path = url ?? defaultURL
        guard let creds = try? load(at: path) else { return false }
        return creds[account] != nil
    }

    // MARK: - Location

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Joint Chiefs", isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
    }

    // MARK: - Internal

    /// Load and decode the credentials dictionary.
    ///
    /// - Throws: `.itemNotFound` when the file is absent; `.ioFailed` when the
    ///           file exists but cannot be read or is not valid JSON.
    private static func load(at path: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw CredentialStoreError.itemNotFound
        }
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw CredentialStoreError.ioFailed(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw CredentialStoreError.ioFailed("credentials file is not valid JSON: \(error.localizedDescription)")
        }
    }

    /// Write the credentials atomically, creating and hardening the parent
    /// directory. File mode `0600`, parent directory `0700`.
    private static func write(_ creds: [String: String], to path: URL) throws {
        let parent = path.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        } catch {
            throw CredentialStoreError.ioFailed("could not prepare \(parent.path): \(error.localizedDescription)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(creds)
        } catch {
            throw CredentialStoreError.encodingFailed
        }

        do {
            try data.write(to: path, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        } catch {
            throw CredentialStoreError.ioFailed("could not write \(path.path): \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

public enum CredentialStoreError: Error, LocalizedError, Sendable {
    case itemNotFound
    case encodingFailed
    case ioFailed(String)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            "No API key found for this provider."
        case .encodingFailed:
            "Failed to encode the credential data."
        case .ioFailed(let detail):
            "Could not read or write the credentials file: \(detail)"
        }
    }
}
