import Foundation
import JointChiefsCore
import Observation

/// Root state for the setup app. Loads any previously saved `StrategyConfig` from
/// disk and exposes draft mutations that are committed either immediately (API
/// keys go straight to the keygetter) or on explicit save (strategy changes).
@Observable
@MainActor
final class SetupModel {

    // MARK: - Navigation

    enum Section: String, CaseIterable, Identifiable {
        case usage = "How to Use"
        case keys = "API Keys"
        case rolesWeights = "Roles & Weights"
        case mcp = "MCP Config"
        case disclosure = "Privacy"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .usage: "book.fill"
            case .keys: "key.fill"
            case .rolesWeights: "slider.horizontal.3"
            case .mcp: "puzzlepiece.extension.fill"
            case .disclosure: "lock.shield"
            }
        }
    }

    var currentSection: Section = .usage

    // MARK: - Strategy (persisted)

    /// The current on-disk strategy, mutated as the user changes roles/weights.
    /// Saved explicitly via `saveStrategy()`.
    var strategy: StrategyConfig

    /// True when the in-memory strategy diverges from what was last loaded/saved.
    private(set) var strategyIsDirty = false

    // MARK: - Keys (not persisted in-memory — live in Keychain)

    enum KeyStatus: Equatable {
        case unconfigured
        case saved
        case testing
        case ok(String)        // model name that worked
        case failed(String)    // error summary
    }

    // Ollama test status — separate from keyStatuses because it isn't key-based.
    enum OllamaStatus: Equatable {
        case unknown
        case testing
        case ok(String)      // model reported by /api/tags or endpoint version
        case failed(String)
    }
    var ollamaStatus: OllamaStatus = .unknown

    // OpenAI-compatible (LM Studio, Jan, llama.cpp, etc.) test status. Same
    // shape as OllamaStatus — the `.ok` payload is a human-readable summary
    // (e.g. "LM Studio · 3 models") instead of a single model string, because
    // /v1/models returns the full roster.
    enum OpenAICompatibleStatus: Equatable {
        case unknown
        case testing
        case ok(String)
        case failed(String)
    }
    var openAICompatibleStatus: OpenAICompatibleStatus = .unknown

    /// Transient staging field — the user types into this, then the "Save" action
    /// writes to the Keychain via the keygetter and clears the field.
    var keyDrafts: [ProviderType: String] = [:]

    /// Live status per provider. Populated from initial Keychain probe plus
    /// per-provider Test actions.
    var keyStatuses: [ProviderType: KeyStatus] = [:]

    // MARK: - CLI install

    enum CLIInstallStatus: Equatable {
        case unknown
        case installing
        case installed(URL)        // path of the destination directory
        case failed(String)        // error summary
    }

    var installDestination: URL = SetupModel.defaultInstallDirectory()
    var cliInstallStatus: CLIInstallStatus = .unknown

    // MARK: - MCP config scan

    /// MCP-server config files discovered on this machine, with per-file
    /// "is Joint Chiefs wired up here?" status. Drives the MCP Config view's
    /// "wired in M of N configs" panel. Empty until `refreshMCPConfigScan()`
    /// runs; refreshed on demand.
    var mcpConfigScan: [MCPConfigScanner.Location] = []
    var mcpConfigScanIsRunning: Bool = false

    // MARK: - Init

    init() {
        self.strategy = StrategyConfigStore.load()
        // Don't probe the Keychain here — the first probe can block behind a
        // macOS access-prompt dialog, which leaves the window blank until the
        // user clicks through. Seed statuses to `.unconfigured` so the UI
        // renders immediately, then call `refreshKeyStatuses()` from a `.task`
        // modifier once the window is on screen.
        for type in ProviderType.allCases {
            keyStatuses[type] = .unconfigured
        }
    }

    /// Async probe of the Keychain to detect existing keys. Runs after the window
    /// is visible so any macOS access-prompt dialog doesn't stall the first paint.
    func refreshKeyStatuses() async {
        for type in ProviderType.allCases {
            guard let account = type.keychainAccount else {
                keyStatuses[type] = .unconfigured // Ollama: local-only
                continue
            }
            do {
                if let existing = try APIKeyResolver.readFromKeygetter(account: account),
                   !existing.isEmpty {
                    keyStatuses[type] = .saved
                } else {
                    keyStatuses[type] = .unconfigured
                }
            } catch {
                keyStatuses[type] = .unconfigured
            }
        }
    }

    // MARK: - Strategy mutations

    func setWeight(_ value: Double, for provider: ProviderType) {
        strategy.providerWeights[provider] = value
        strategyIsDirty = true
    }

    /// Sets a user-specified model override for a provider. Auto-persists
    /// (like Ollama fields) because users expect "typed a model → it applies
    /// next review" — no hunting for a Save button. Empty strings remove the
    /// override so ProviderFactory falls back to env var / default.
    func setProviderModel(_ value: String, for provider: ProviderType) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            strategy.providerModels.removeValue(forKey: provider)
        } else {
            strategy.providerModels[provider] = trimmed
        }
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func setModerator(_ selection: ModeratorSelection) {
        strategy.moderator = selection
        strategyIsDirty = true
    }

    func setTiebreaker(_ selection: TiebreakerSelection) {
        strategy.tiebreaker = selection
        strategyIsDirty = true
    }

    func setConsensus(_ mode: ConsensusMode) {
        strategy.consensus = mode
        strategyIsDirty = true
    }

    func setMaxRounds(_ rounds: Int) {
        strategy.maxRounds = rounds
        strategyIsDirty = true
    }

    func setTimeoutSeconds(_ seconds: Int) {
        strategy.timeoutSeconds = seconds
        strategyIsDirty = true
    }

    func setThresholdPercent(_ percent: Double) {
        strategy.thresholdPercent = percent
        strategyIsDirty = true
    }

    // Ollama mutations auto-persist because they live on the Keys screen, which
    // uses immediate-write UX (same pattern as Save/Delete Key). Users expect
    // "flip a toggle → it's on" without hunting for a global Save button.
    func setOllamaEnabled(_ enabled: Bool) {
        strategy.ollama.enabled = enabled
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func setOllamaModel(_ model: String) {
        strategy.ollama.model = model
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func setOllamaEndpoint(_ endpoint: String) {
        strategy.ollama.endpoint = endpoint
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func testOllamaConnection() async {
        ollamaStatus = .testing
        let endpoint = strategy.ollama.endpoint
        guard let url = URL(string: endpoint) else {
            ollamaStatus = .failed("Invalid URL: \(endpoint)")
            return
        }
        let provider = OllamaProvider(model: strategy.ollama.model, endpoint: url)
        do {
            let ok = try await provider.testConnection()
            ollamaStatus = ok ? .ok(strategy.ollama.model) : .failed("Server returned non-2xx")
        } catch {
            ollamaStatus = .failed(error.localizedDescription)
        }
    }

    // OpenAI-compatible mutations — same immediate-persist pattern as Ollama.
    func setOpenAICompatibleEnabled(_ enabled: Bool) {
        strategy.openAICompatible.enabled = enabled
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func setOpenAICompatibleEndpoint(_ endpoint: String) {
        strategy.openAICompatible.endpoint = endpoint
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func setOpenAICompatibleModel(_ model: String) {
        strategy.openAICompatible.model = model
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func setOpenAICompatibleAPIKey(_ key: String) {
        strategy.openAICompatible.apiKey = key
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func setOpenAICompatiblePreset(_ preset: String) {
        strategy.openAICompatible.presetName = preset
        // Pre-fill the endpoint when the user picks a known preset, but only
        // if the field is empty or still holds another preset's default —
        // don't clobber a hand-edited endpoint.
        let presetDefaults: [String: String] = [
            "LM Studio": "http://localhost:1234/v1",
            "Jan": "http://localhost:1337/v1",
            "llama.cpp": "http://localhost:8080/v1",
        ]
        let currentEndpoint = strategy.openAICompatible.endpoint
        let isDefaultEndpoint = presetDefaults.values.contains(currentEndpoint) || currentEndpoint.isEmpty
        if isDefaultEndpoint, let newDefault = presetDefaults[preset] {
            strategy.openAICompatible.endpoint = newDefault
        }
        try? StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    func testOpenAICompatibleConnection() async {
        openAICompatibleStatus = .testing
        let endpoint = strategy.openAICompatible.endpoint
        guard let url = URL(string: endpoint) else {
            openAICompatibleStatus = .failed("Invalid URL: \(endpoint)")
            return
        }
        // Probe /v1/models directly — that's how clients discover what's
        // loaded on LM Studio / Jan / llama.cpp. A 200 with a non-empty `data`
        // array means the server is reachable and has at least one model.
        let modelsURL = url.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        let apiKey = strategy.openAICompatible.apiKey
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = TimeInterval(strategy.openAICompatible.timeoutSeconds)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                openAICompatibleStatus = .failed("Non-HTTP response")
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                openAICompatibleStatus = .failed("HTTP \(http.statusCode)")
                return
            }
            // Parse model list loosely — { "data": [{"id": "..."}, ...] }
            struct ModelListResponse: Decodable {
                struct Entry: Decodable { let id: String }
                let data: [Entry]
            }
            let parsed = try? JSONDecoder().decode(ModelListResponse.self, from: data)
            let count = parsed?.data.count ?? 0
            let presetName = strategy.openAICompatible.presetName
            openAICompatibleStatus = .ok("\(presetName) · \(count) model\(count == 1 ? "" : "s")")
        } catch {
            openAICompatibleStatus = .failed(error.localizedDescription)
        }
    }

    func saveStrategy() throws {
        try StrategyConfigStore.save(strategy)
        strategyIsDirty = false
    }

    // MARK: - Key mutations

    func saveKey(_ key: String, for provider: ProviderType) async {
        guard let account = provider.keychainAccount else { return }
        do {
            try APIKeyResolver.writeViaKeygetter(account: account, key: key)
            keyStatuses[provider] = .saved
            keyDrafts[provider] = ""
        } catch {
            keyStatuses[provider] = .failed(error.localizedDescription)
        }
    }

    func deleteKey(for provider: ProviderType) async {
        guard let account = provider.keychainAccount else { return }
        do {
            try APIKeyResolver.deleteViaKeygetter(account: account)
            keyStatuses[provider] = .unconfigured
        } catch {
            keyStatuses[provider] = .failed(error.localizedDescription)
        }
    }

    func testKey(for provider: ProviderType) async {
        keyStatuses[provider] = .testing
        do {
            guard let resolved = try APIKeyResolver.resolve(provider), !resolved.isEmpty else {
                keyStatuses[provider] = .failed("No key configured.")
                return
            }
            let testProvider = ProviderFactoryForSetup.build(provider, apiKey: resolved)
            guard let testProvider else {
                keyStatuses[provider] = .ok(provider.defaultModel)
                return
            }
            let ok = try await testProvider.testConnection()
            keyStatuses[provider] = ok ? .ok(testProvider.model) : .failed("Test returned false.")
        } catch {
            keyStatuses[provider] = .failed(error.localizedDescription)
        }
    }

    // MARK: - CLI install

    /// Copies `jointchiefs`, `jointchiefs-mcp`, `jointchiefs-keygetter` from the
    /// app bundle (or `.build/release` for dev) into `installDestination`. Skips
    /// files that already match by size — common when installed via Homebrew
    /// cask, which symlinks the same binaries from the bundle, or when the user
    /// has launched the wizard before.
    func installCLIIfNeeded() async {
        // If installation already completed in this session, no-op.
        if case .installing = cliInstallStatus { return }
        if case .installed = cliInstallStatus { return }

        cliInstallStatus = .installing

        let destination = installDestination
        guard let sourceDir = Self.bundledBinariesDir() else {
            cliInstallStatus = .failed("Could not locate bundled CLI binaries.")
            return
        }

        let binaries = ["jointchiefs", "jointchiefs-mcp", "jointchiefs-keygetter"]

        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            for name in binaries {
                let src = sourceDir.appendingPathComponent(name)
                let dst = destination.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: src.path) else {
                    cliInstallStatus = .failed("Missing \(name) in bundle at \(sourceDir.path).")
                    return
                }
                if Self.binariesMatch(src: src, dst: dst) {
                    continue   // already installed (cask symlink or prior wizard run)
                }
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: src, to: dst)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: dst.path
                )
            }
            cliInstallStatus = .installed(destination)
        } catch {
            cliInstallStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - MCP config scan

    /// Re-runs the MCP config scan. Call from `.task` on MCP Config view appear
    /// and from a Refresh button. Off-loads I/O to a detached task so the home
    /// directory walk doesn't block the main thread.
    func refreshMCPConfigScan() async {
        if mcpConfigScanIsRunning { return }
        mcpConfigScanIsRunning = true
        let results = await Task.detached(priority: .utility) {
            MCPConfigScanner.scan()
        }.value
        mcpConfigScan = results
        mcpConfigScanIsRunning = false
    }

    /// Forces a re-install to a user-chosen destination. Used by the recovery
    /// affordance in MCP Config when the default destination wasn't writable.
    func reinstallCLI(to destination: URL) async {
        installDestination = destination
        cliInstallStatus = .unknown
        await installCLIIfNeeded()
    }

    /// True when the destination already has a binary that matches `src` by
    /// size. Cheap check — full SHA would be more correct but the bundle binary
    /// is the only legitimate source of these names so size collisions are
    /// effectively impossible.
    private static func binariesMatch(src: URL, dst: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dst.path) else { return false }
        do {
            let srcAttrs = try fm.attributesOfItem(atPath: src.path)
            let dstAttrs = try fm.attributesOfItem(atPath: dst.path)
            let srcSize = (srcAttrs[.size] as? NSNumber)?.intValue ?? -1
            let dstSize = (dstAttrs[.size] as? NSNumber)?.intValue ?? -2
            return srcSize == dstSize && srcSize > 0
        } catch {
            return false
        }
    }

    /// Finds the directory containing the three CLI binaries to copy. Two shapes:
    ///
    /// - `.build/release/` (development via `swift run`): the setup exe sits next
    ///   to its siblings. Return the exe's directory.
    /// - `Joint Chiefs.app/Contents/MacOS/jointchiefs-setup` (bundled): the setup
    ///   exe is in `Contents/MacOS/`, but the CLI binaries live in
    ///   `Contents/Resources/`. Return the Resources directory.
    static func bundledBinariesDir() -> URL? {
        let exe = CommandLine.arguments.first ?? ""
        let resolved = URL(fileURLWithPath: exe).resolvingSymlinksInPath()
        let exeDir = resolved.deletingLastPathComponent()
        let cliSibling = exeDir.appendingPathComponent("jointchiefs")
        if FileManager.default.isExecutableFile(atPath: cliSibling.path) {
            return exeDir
        }
        let resourcesDir = exeDir
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let cliInResources = resourcesDir.appendingPathComponent("jointchiefs")
        if FileManager.default.isExecutableFile(atPath: cliInResources.path) {
            return resourcesDir
        }
        return nil
    }

    // MARK: - Defaults

    private static func defaultInstallDirectory() -> URL {
        // Apple Silicon Homebrew prefix first — matches where the existing CLI
        // install lives (see BUILD-PLAN Phase 5).
        let homebrew = URL(fileURLWithPath: "/opt/homebrew/bin")
        if FileManager.default.isWritableFile(atPath: homebrew.path) {
            return homebrew
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin")
    }
}

// MARK: - Provider Builder (Setup-scoped)

/// Builds a single provider for the setup app's Test action, without the
/// panel-assembly filtering that `ProviderFactory.buildPanel` performs. The
/// setup context is "user just typed a key — does it work" so we always build
/// the provider regardless of weight.
enum ProviderFactoryForSetup {
    static func build(_ type: ProviderType, apiKey: String) -> (any ReviewProvider)? {
        switch type {
        case .openAI:
            return OpenAIProvider(apiKey: apiKey, model: type.defaultModel)
        case .gemini:
            return GeminiProvider(apiKey: apiKey, model: type.defaultModel)
        case .grok:
            return GrokProvider(apiKey: apiKey, model: type.defaultModel)
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey, model: type.defaultModel)
        case .ollama:
            return nil
        case .openAICompatible:
            // Tested via OpenAICompatibleCard's own Test button against the
            // configured `/v1/models` endpoint — not through the generic
            // Save/Test path other providers use.
            return nil
        }
    }
}
