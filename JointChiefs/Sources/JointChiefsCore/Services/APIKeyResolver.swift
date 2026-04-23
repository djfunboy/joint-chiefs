import Foundation

/// Resolves API keys for LLM providers by trying, in order:
///
///   1. Environment variable (CI-only escape hatch; documented as such).
///   2. Spawning `jointchiefs-keygetter` via `Process` and reading stdout.
///
/// The keygetter is the single signed binary permitted to touch Joint Chiefs'
/// Keychain items — see `Sources/JointChiefsKeygetter/main.swift`. Every runtime
/// caller (CLI, MCP server) funnels through this resolver so we only spawn and
/// drop the key at the exact moment of use.
///
/// Returning `nil` means "this provider is not configured." Throwing means the
/// provider is configured but access failed (keygetter crashed, keychain locked,
/// etc.) — callers should surface that to the user rather than silently skip.
public enum APIKeyResolver {

    // MARK: - Public API

    /// Resolve the API key for a given provider. Returns `nil` if neither the
    /// env var nor the Keychain has a key for this provider.
    public static func resolve(_ provider: ProviderType) throws -> String? {
        if let key = env(provider.envVarName), !key.isEmpty {
            return key
        }
        guard let account = provider.keychainAccount else {
            return nil
        }
        return try readFromKeygetter(account: account)
    }

    /// Read a key for an arbitrary account (used by the setup app to verify
    /// writes and by tests). Mirrors `resolve(_:)` but without env-var fallback.
    public static func readFromKeygetter(account: String) throws -> String? {
        guard let keygetterPath = locateKeygetter() else {
            return nil
        }
        return try invoke(path: keygetterPath, arguments: ["read", account])
    }

    /// Write a key via the keygetter. Used by the setup app so the Keychain ACL
    /// stays bound to the single keygetter identity rather than each surface that
    /// writes a key.
    public static func writeViaKeygetter(account: String, key: String) throws {
        guard let keygetterPath = locateKeygetter() else {
            throw APIKeyResolverError.keygetterFailed(
                exitCode: -1,
                stderr: "keygetter binary not found"
            )
        }
        _ = try invoke(path: keygetterPath, arguments: ["write", account, key])
    }

    /// Delete a key via the keygetter.
    public static func deleteViaKeygetter(account: String) throws {
        guard let keygetterPath = locateKeygetter() else {
            throw APIKeyResolverError.keygetterFailed(
                exitCode: -1,
                stderr: "keygetter binary not found"
            )
        }
        _ = try invoke(path: keygetterPath, arguments: ["delete", account])
    }

    // MARK: - Keygetter Discovery

    /// Finds the `jointchiefs-keygetter` binary.
    ///
    ///   1. `JOINTCHIEFS_KEYGETTER_PATH` — absolute user override. If set, this
    ///      is the only path consulted: a non-executable value returns nil
    ///      rather than silently falling through to a different keygetter
    ///      identity than the user asked for.
    ///   2. Sibling of current executable (e.g., `~/.local/bin/jointchiefs-keygetter`
    ///      next to `~/.local/bin/jointchiefs`).
    ///   3. `../Resources/` relative to the running executable — covers the
    ///      setup app running from `Joint Chiefs.app/Contents/MacOS/`.
    ///   4. App bundle: `/Applications/Joint Chiefs.app/Contents/Resources/jointchiefs-keygetter`.
    public static func locateKeygetter() -> String? {
        if let override = env("JOINTCHIEFS_KEYGETTER_PATH") {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        for candidate in defaultSearchPaths() {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Internal

    private static func defaultSearchPaths() -> [String] {
        var paths: [String] = []
        // 1. Sibling of the running executable. Works for CLI + MCP in any
        //    install directory (jointchiefs and jointchiefs-keygetter land together).
        if let sibling = siblingPath(for: "jointchiefs-keygetter") {
            paths.append(sibling)
        }
        // 2. `../Resources/` relative to the running executable. The setup app
        //    runs from `Joint Chiefs.app/Contents/MacOS/jointchiefs-setup` while
        //    its sibling CLIs live in `Contents/Resources/` — standard bundle
        //    layout, not the `MacOS/` directory, so a flat sibling lookup misses.
        if let resourcesRelative = resourcesSiblingPath(for: "jointchiefs-keygetter") {
            paths.append(resourcesRelative)
        }
        // 3. Default install location for /Applications bundles.
        paths.append("/Applications/Joint Chiefs.app/Contents/Resources/jointchiefs-keygetter")
        return paths
    }

    private static func siblingPath(for name: String) -> String? {
        let executablePath = CommandLine.arguments.first ?? ""
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        return resolved.deletingLastPathComponent().appendingPathComponent(name).path
    }

    private static func resourcesSiblingPath(for name: String) -> String? {
        let executablePath = CommandLine.arguments.first ?? ""
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        return resolved
            .deletingLastPathComponent()          // drop exe name
            .deletingLastPathComponent()          // drop MacOS/
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(name)
            .path
    }

    /// Spawn the keygetter, capture stdout, and return the trimmed key.
    ///
    /// - Returns: The key, or `nil` if the keygetter reports `item not found` (exit 3).
    /// - Throws: `APIKeyResolverError` for other keygetter failures (interaction
    ///           disabled, keychain error, spawn failure, etc.).
    private static func invoke(path: String, arguments: [String]) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = Pipe()

        do {
            try process.run()
        } catch {
            throw APIKeyResolverError.spawnFailed(path: path, underlying: error)
        }
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        switch process.terminationStatus {
        case 0:
            guard let key = String(data: stdoutData, encoding: .utf8), !key.isEmpty else {
                throw APIKeyResolverError.decodeFailed
            }
            return key
        case 3:
            return nil
        case 4:
            throw APIKeyResolverError.interactionNotAllowed
        default:
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            throw APIKeyResolverError.keygetterFailed(exitCode: process.terminationStatus, stderr: message)
        }
    }

    private static func env(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name]
    }
}

// MARK: - Errors

public enum APIKeyResolverError: Error, LocalizedError, Sendable {
    case spawnFailed(path: String, underlying: Error)
    case decodeFailed
    case interactionNotAllowed
    case keygetterFailed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .spawnFailed(let path, let underlying):
            "Could not spawn keygetter at \(path): \(underlying.localizedDescription)"
        case .decodeFailed:
            "Keygetter returned invalid UTF-8 output."
        case .interactionNotAllowed:
            "Keychain requires user interaction but the process is running headlessly."
        case .keygetterFailed(let code, let stderr):
            "Keygetter exited with status \(code): \(stderr)"
        }
    }
}

// MARK: - ProviderType helpers

extension ProviderType {

    /// Environment variable consulted before the Keychain (CI escape hatch).
    public var envVarName: String {
        switch self {
        case .openAI: "OPENAI_API_KEY"
        case .anthropic: "ANTHROPIC_API_KEY"
        case .gemini: "GEMINI_API_KEY"
        case .grok: "GROK_API_KEY"
        case .ollama: "OLLAMA_API_KEY"
        case .openAICompatible: "OPENAI_COMPATIBLE_API_KEY"
        }
    }

    /// Keychain account name for this provider. Ollama is local-only and has no
    /// stored credential, so it returns nil. OpenAI-compatible providers store
    /// their (usually-empty) key directly in `StrategyConfig.openAICompatible.apiKey`
    /// rather than in the Keychain — simpler for the 95% case where local servers
    /// don't authenticate.
    public var keychainAccount: String? {
        switch self {
        case .openAI: "openai"
        case .anthropic: "anthropic"
        case .gemini: "gemini"
        case .grok: "grok"
        case .ollama: nil
        case .openAICompatible: nil
        }
    }
}
