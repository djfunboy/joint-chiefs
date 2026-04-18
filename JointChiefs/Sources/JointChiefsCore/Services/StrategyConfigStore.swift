import Foundation

/// Reads and writes `StrategyConfig` to disk.
///
/// Default path: `~/Library/Application Support/Joint Chiefs/strategy.json`.
/// Written by the setup app, consumed by the CLI and MCP server. File mode 0600
/// on write — the strategy is non-secret user preference but there's no reason
/// to expose it to other local users.
///
/// On load, a missing file returns `.default` silently; a malformed file logs
/// to stderr and returns `.default` so the binary can still run.
public enum StrategyConfigStore {

    // MARK: - Public API

    /// Load the user's strategy from disk. Returns `.default` on any failure,
    /// so callers never need to handle the absent-file case.
    public static func load(at url: URL? = nil) -> StrategyConfig {
        let path = url ?? defaultURL
        guard FileManager.default.fileExists(atPath: path.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: path)
            return try JSONDecoder().decode(StrategyConfig.self, from: data)
        } catch {
            let message = "[strategy] could not load \(path.path): \(error.localizedDescription) — falling back to defaults\n"
            FileHandle.standardError.write(Data(message.utf8))
            return .default
        }
    }

    /// Write the strategy atomically, creating the parent directory if needed.
    /// File mode is set to 0600.
    public static func save(_ config: StrategyConfig, to url: URL? = nil) throws {
        let path = url ?? defaultURL
        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: path, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    // MARK: - Location

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Joint Chiefs", isDirectory: true)
            .appendingPathComponent("strategy.json", isDirectory: false)
    }
}
