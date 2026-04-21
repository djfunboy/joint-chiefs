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
        case disclosure = "Data Handling"
        case keys = "API Keys"
        case rolesWeights = "Roles & Weights"
        case install = "Install"
        case mcp = "MCP Config"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .disclosure: "lock.shield"
            case .keys: "key.fill"
            case .rolesWeights: "slider.horizontal.3"
            case .install: "square.and.arrow.down"
            case .mcp: "terminal"
            }
        }
    }

    var currentSection: Section = .disclosure

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

    /// Transient staging field — the user types into this, then the "Save" action
    /// writes to the Keychain via the keygetter and clears the field.
    var keyDrafts: [ProviderType: String] = [:]

    /// Live status per provider. Populated from initial Keychain probe plus
    /// per-provider Test actions.
    var keyStatuses: [ProviderType: KeyStatus] = [:]

    // MARK: - Install

    var installDestination: URL = SetupModel.defaultInstallDirectory()
    var pathNeedsUpdate: Bool = false

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
        }
    }
}
