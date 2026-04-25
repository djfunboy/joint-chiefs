import Foundation

/// Scans the user's home directory for files that look like MCP-server config
/// stores and reports which ones have a Joint Chiefs entry. Drives the
/// MCP Config view's "wired in M of N configs" panel.
///
/// Stays generic on purpose — never matches by app or client name. Detection
/// is by *shape*: a JSON file with an `mcpServers` map, or a TOML file with
/// an `[mcp_servers...]` table. Whatever future MCP-aware tools follow those
/// conventions will be picked up automatically; nothing in this code, or in
/// the strings it surfaces, names a specific client.
enum MCPConfigScanner {

    struct Location: Identifiable, Equatable, Sendable {
        let path: URL
        let format: Format
        let hasJointChiefsEntry: Bool
        var id: URL { path }
    }

    enum Format: String, Sendable { case json, toml }

    /// Largest file we'll inspect. Some "config" paths (notably JSON state
    /// stores) accumulate megabytes of session history; the MCP-server
    /// stanza is always at the top and these aren't the files we care about
    /// once they're that big — bail rather than slurp the whole thing.
    private static let maxFileSizeBytes = 8 * 1024 * 1024

    /// Sanity ceiling on how many candidate files we inspect per scan. Prevents
    /// runaway I/O if a future macOS surface ends up with thousands of small
    /// JSON files under one of our scan roots. Far above the realistic case
    /// (a typical machine produces a few dozen candidates after filtering).
    private static let maxCandidateCount = 500

    /// Run the scan. Cheap enough to call from a `.task` modifier; bounded
    /// by the curated location patterns and a noise-dir skip-list rather
    /// than a full home walk.
    static func scan() -> [Location] {
        let candidates = candidatePaths()
        var results: [Location] = []
        for path in candidates {
            guard let location = inspect(path: path) else { continue }
            results.append(location)
        }
        return results.sorted { $0.path.path < $1.path.path }
    }

    // MARK: - Candidate enumeration

    /// Generic noise-dir skip-list. These names are storage/cache/runtime
    /// substrates used across many apps (most are Chromium/Electron-derived);
    /// none of them are client names, so listing them here doesn't violate
    /// the "no specific client enumeration" rule. Lowercased for matching.
    private static let noiseDirNames: Set<String> = [
        "cache", "caches", "code cache", "gpucache",
        "dawngraphitecache", "dawnwebgpucache",
        "shared dictionary", "sharedstorage",
        "indexeddb", "local storage", "session storage",
        "blob_storage", "service worker", "shared_proto_db",
        "network persistent state", "partitions",
        "crashpad", "crashreporter", "crash reports",
        "trust tokens", "transportsecurity",
        "logs", "log",
        "tmp", "temp",
        "node_modules",
        ".trash", "trash",
        "videodecodestats", "webstorage",
        "fcache", "sentry",
    ]

    private static func shouldSkipDir(_ name: String) -> Bool {
        noiseDirNames.contains(name.lowercased())
    }

    private static func candidatePaths() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default
        var paths: [URL] = []

        // Round 1 — top-level dotfiles directly in $HOME.
        if let names = try? fm.contentsOfDirectory(atPath: home.path) {
            for name in names where name.hasPrefix(".") {
                let url = home.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                if isInterestingFile(url) { paths.append(url) }
            }
        }

        // Round 2 — hidden dirs at $HOME, recurse one extra level inside each
        // (catches `~/.codex/config.toml` and `~/.<dir>/<sub>/<file>`).
        if let names = try? fm.contentsOfDirectory(atPath: home.path) {
            for name in names where name.hasPrefix(".") {
                let dir = home.appendingPathComponent(name, isDirectory: true)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if shouldSkipDir(name) { continue }
                paths.append(contentsOf: collectInterestingFiles(in: dir, depth: 1))
            }
        }

        // Round 3 — XDG-style ~/.config/<app>/...
        let xdg = home.appendingPathComponent(".config", isDirectory: true)
        paths.append(contentsOf: collectInterestingFiles(in: xdg, depth: 2))

        // Round 4 — ~/Library/Application Support/<app>/...  Depth 2 catches
        // the `<app>/User/<file>` shape used by editor-derived AI tools.
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        paths.append(contentsOf: collectInterestingFiles(in: appSupport, depth: 2))

        // De-duplicate while preserving order; cap at the sanity ceiling.
        var seen = Set<String>()
        var result: [URL] = []
        for p in paths {
            let key = p.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(p)
                if result.count >= maxCandidateCount { break }
            }
        }
        return result
    }

    /// Walks `dir` collecting interesting files, recursing into subdirectories
    /// up to `depth` more levels. At `depth == 0`, only direct child files are
    /// returned. Skips hidden entries (drops `.git`, `.cache`, etc. for free)
    /// and any directory whose name appears in the generic noise list.
    private static func collectInterestingFiles(in dir: URL, depth: Int) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if depth > 0, !shouldSkipDir(url.lastPathComponent) {
                    files.append(contentsOf: collectInterestingFiles(in: url, depth: depth - 1))
                }
            } else if isInterestingFile(url) {
                files.append(url)
            }
        }
        return files
    }

    private static func isInterestingFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".json") || name.hasSuffix(".toml") { return true }
        // A few tools use unextensioned `config` or `settings` files in TOML or JSON form.
        if name == "config" || name == "settings" { return true }
        return false
    }

    // MARK: - File inspection

    private static func inspect(path: URL) -> Location? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              size > 0,
              size <= maxFileSizeBytes
        else { return nil }

        guard let data = try? Data(contentsOf: path, options: [.mappedIfSafe]),
              let contents = String(data: data, encoding: .utf8)
        else { return nil }

        guard let format = detectFormat(name: path.lastPathComponent, contents: contents) else { return nil }

        // Cheap pre-filter — skip files that obviously can't be MCP configs.
        guard hasMCPServerSignature(format: format, contents: contents) else { return nil }

        // Structural confirmation. A file that just *mentions* "mcpServers" in
        // a string value (e.g. a state cache or backup) shouldn't be surfaced
        // as a config; we require a real structured stanza.
        guard let hasJC = structuralCheck(format: format, data: data, contents: contents) else { return nil }

        return Location(path: path, format: format, hasJointChiefsEntry: hasJC)
    }

    private static func detectFormat(name: String, contents: String) -> Format? {
        let lower = name.lowercased()
        if lower.hasSuffix(".json") { return .json }
        if lower.hasSuffix(".toml") { return .toml }
        // Unextensioned: sniff by leading non-whitespace char.
        let trimmed = contents.drop { $0.isWhitespace || $0.isNewline }
        guard let first = trimmed.first else { return nil }
        if first == "{" || first == "[" {
            return contents.contains("\":") ? .json : (contents.contains(" = ") ? .toml : .json)
        }
        return nil
    }

    /// Cheap substring pre-filter. The structural check below is the one that
    /// actually decides inclusion.
    private static func hasMCPServerSignature(format: Format, contents: String) -> Bool {
        switch format {
        case .json:
            return contents.contains("\"mcpServers\"")
        case .toml:
            return contents.range(of: #"\[\s*mcp_servers"#, options: .regularExpression) != nil
        }
    }

    /// Returns `nil` when the file doesn't actually contain a structured
    /// MCP-server stanza (so it should be excluded from the scan results
    /// entirely). Returns `true`/`false` for "is, with JC" / "is, without JC".
    private static func structuralCheck(format: Format, data: Data, contents: String) -> Bool? {
        switch format {
        case .json:
            guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return nil
            }
            guard jsonContainsMCPServersMap(root) else { return nil }
            return jsonContainsJointChiefsServer(root)
        case .toml:
            // Match `[mcp_servers]` or `[mcp_servers.<name>]` (with optional
            // quoted name and whitespace tolerance).
            let stanza = #"\[\s*mcp_servers(\s*\.\s*"?[^\s\]"]+"?)?\s*\]"#
            guard contents.range(of: stanza, options: .regularExpression) != nil else { return nil }
            let jcStanza = #"\[\s*mcp_servers\s*\.\s*"?joint[-_]?chiefs"?\s*\]"#
            return contents.range(of: jcStanza, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// True if any nested JSON object has an `mcpServers` value that is itself
    /// an object. Some tools nest `mcpServers` under per-project keys
    /// (e.g. `{ projects: { "/path": { mcpServers: { ... } } } }`); recursive
    /// walk handles both shapes.
    private static func jsonContainsMCPServersMap(_ value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            if dict["mcpServers"] is [String: Any] { return true }
            for v in dict.values where jsonContainsMCPServersMap(v) { return true }
            return false
        }
        if let array = value as? [Any] {
            return array.contains { jsonContainsMCPServersMap($0) }
        }
        return false
    }

    /// True if any nested `mcpServers` object contains a Joint Chiefs entry.
    /// Matches the same lenient set of variants the MCP tool description
    /// accepts, but only as structured map keys — not as substrings appearing
    /// elsewhere in the file (a common false positive in large state files
    /// that mention project paths or filenames containing "joint-chiefs").
    private static func jsonContainsJointChiefsServer(_ value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            if let servers = dict["mcpServers"] as? [String: Any] {
                for key in servers.keys where isJointChiefsKey(key) { return true }
            }
            for child in dict.values {
                if jsonContainsJointChiefsServer(child) { return true }
            }
            return false
        }
        if let array = value as? [Any] {
            return array.contains { jsonContainsJointChiefsServer($0) }
        }
        return false
    }

    private static func isJointChiefsKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower == "joint-chiefs" || lower == "joint_chiefs" || lower == "jointchiefs"
    }
}
