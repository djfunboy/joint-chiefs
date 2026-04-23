import Foundation

/// Constructs `ReviewProvider` instances from a `ProviderType` or `ModeratorSelection`
/// using a caller-supplied key resolver closure. Shared by the CLI and MCP surfaces so
/// panel assembly and moderator/tiebreaker resolution stay identical across entry points.
///
/// The resolver closure is caller-owned because CLI and MCP have different error-reporting
/// channels: the CLI writes to its own stderr helper, while MCP writes directly to
/// `FileHandle.standardError` (headless, no user-facing output). Both funnel through
/// `APIKeyResolver` underneath.
public enum ProviderFactory {

    // MARK: - Panel Assembly

    /// Build the spoke panel — every provider with a resolvable key, plus Ollama when
    /// explicitly enabled via `StrategyConfig.ollama` or the `OLLAMA_ENABLED` env var.
    /// Preserves the ordering used by the pre-refactor callers (OpenAI, Gemini, Grok,
    /// Anthropic, Ollama) so existing tests remain stable.
    ///
    /// - Parameters:
    ///   - resolveKey: Closure that returns the API key for a provider, or nil.
    ///   - weights: Optional per-provider weights. A weight of `0.0` (or any
    ///     non-positive value) excludes the provider from the panel regardless of key
    ///     availability. Nil means "no weighting applied" (v1 behavior).
    ///   - ollama: Optional Ollama configuration (enabled/model/endpoint). When set,
    ///     overrides the `OLLAMA_ENABLED` / `OLLAMA_MODEL` env-var path; the env vars
    ///     still win if *explicitly* set in the environment, as a CI override.
    ///   - env: Process environment, injectable for tests.
    public static func buildPanel(
        resolveKey: (ProviderType) -> String?,
        weights: [ProviderType: Double]? = nil,
        models: [ProviderType: String]? = nil,
        ollama: OllamaConfig? = nil,
        openAICompatible: OpenAICompatibleConfig? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [any ReviewProvider] {
        var providers: [any ReviewProvider] = []

        func isExcluded(_ type: ProviderType) -> Bool {
            guard let weights else { return false }
            guard let weight = weights[type] else { return false }
            return weight <= 0
        }

        // Model resolution priority per provider:
        //   1. `models[type]` — user's StrategyConfig override (empty string ignored)
        //   2. env var (OPENAI_MODEL, ANTHROPIC_MODEL, etc.) — CI / dev override
        //   3. ProviderType.defaultModel — shipped default
        func resolveModel(_ type: ProviderType, envKey: String) -> String {
            if let override = models?[type], !override.isEmpty {
                return override
            }
            if let envValue = env[envKey], !envValue.isEmpty {
                return envValue
            }
            return type.defaultModel
        }

        let session = HardenedURLSession.shared

        if !isExcluded(.openAI), let key = resolveKey(.openAI) {
            providers.append(OpenAIProvider(
                apiKey: key,
                model: resolveModel(.openAI, envKey: "OPENAI_MODEL"),
                urlSession: session
            ))
        }
        if !isExcluded(.gemini), let key = resolveKey(.gemini) {
            providers.append(GeminiProvider(
                apiKey: key,
                model: resolveModel(.gemini, envKey: "GEMINI_MODEL"),
                urlSession: session
            ))
        }
        if !isExcluded(.grok), let key = resolveKey(.grok) {
            providers.append(GrokProvider(
                apiKey: key,
                model: resolveModel(.grok, envKey: "GROK_MODEL"),
                urlSession: session
            ))
        }
        if !isExcluded(.anthropic), let key = resolveKey(.anthropic) {
            providers.append(AnthropicProvider(
                apiKey: key,
                model: resolveModel(.anthropic, envKey: "ANTHROPIC_MODEL"),
                urlSession: session
            ))
        }

        // Ollama resolution priority:
        //   1. OLLAMA_ENABLED env var set explicitly to "1" → include; "0" → exclude.
        //      (CI override — mirrors the API-key env-var-first pattern.)
        //   2. Otherwise, use `ollama.enabled` from StrategyConfig.
        //   3. If neither path enables Ollama, skip it.
        //
        // Model/endpoint resolution follows the same layering: env var first, then
        // the StrategyConfig, then hardcoded defaults.
        let ollamaEnabled: Bool = {
            if let envFlag = env["OLLAMA_ENABLED"] {
                return envFlag == "1"
            }
            return ollama?.enabled ?? false
        }()
        if !isExcluded(.ollama), ollamaEnabled {
            let model = env["OLLAMA_MODEL"] ?? ollama?.model ?? ProviderType.ollama.defaultModel
            let endpointString = ollama?.endpoint ?? "http://localhost:11434"
            let timeout = ollama?.timeoutSeconds ?? 600
            if let url = URL(string: endpointString) {
                providers.append(OllamaProvider(model: model, endpoint: url, timeoutSeconds: timeout))
            } else {
                providers.append(OllamaProvider(model: model, timeoutSeconds: timeout))
            }
        }

        // OpenAI-compatible local server (LM Studio, Jan, llama.cpp-server, etc.)
        // Resolution precedence mirrors Ollama:
        //   1. `OPENAI_COMPATIBLE_BASE_URL` / `OPENAI_COMPATIBLE_MODEL` env vars
        //      (CI fallback). If either is set, the server is considered
        //      enabled even when `StrategyConfig.openAICompatible.enabled` is false.
        //   2. Otherwise, `openAICompatible.enabled` from StrategyConfig.
        let openAICompatEnabled: Bool = {
            if env["OPENAI_COMPATIBLE_BASE_URL"] != nil || env["OPENAI_COMPATIBLE_MODEL"] != nil {
                return true
            }
            return openAICompatible?.enabled ?? false
        }()
        if !isExcluded(.openAICompatible), openAICompatEnabled {
            let endpointString = env["OPENAI_COMPATIBLE_BASE_URL"]
                ?? openAICompatible?.endpoint
                ?? "http://localhost:1234/v1"
            let modelName = env["OPENAI_COMPATIBLE_MODEL"]
                ?? openAICompatible?.model
                ?? ""
            let apiKey = env["OPENAI_COMPATIBLE_API_KEY"]
                ?? openAICompatible?.apiKey
                ?? ""
            let timeout = openAICompatible?.timeoutSeconds ?? 600
            let displayName = openAICompatible?.presetName ?? "LM Studio"
            // Skip if the caller forgot to configure a model — there's nothing
            // meaningful to send. Logging falls back to the orchestrator's own
            // panel-empty error surface.
            if !modelName.isEmpty, let url = URL(string: endpointString) {
                providers.append(OpenAICompatibleProvider(
                    endpoint: url,
                    model: modelName,
                    apiKey: apiKey,
                    timeoutSeconds: timeout,
                    displayName: displayName
                ))
            }
        }

        return providers
    }

    // MARK: - Moderator / Tiebreaker

    /// Build the provider instance for a `ModeratorSelection`. Returns nil for
    /// `.none` (code-based fallback), for Ollama (never a valid moderator), or when
    /// the selected provider's key can't be resolved.
    ///
    /// Anthropic resolves its model via `CONSENSUS_MODEL` first, matching the pre-refactor
    /// behavior so operators can split per-round Claude from the deciding Claude.
    public static func build(
        for selection: ModeratorSelection,
        resolveKey: (ProviderType) -> String?,
        models: [ProviderType: String]? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any ReviewProvider)? {
        guard let type = selection.providerType else { return nil }
        guard let key = resolveKey(type) else { return nil }

        func resolveModel(_ type: ProviderType, envKey: String) -> String {
            if let override = models?[type], !override.isEmpty {
                return override
            }
            if let envValue = env[envKey], !envValue.isEmpty {
                return envValue
            }
            return type.defaultModel
        }

        let session = HardenedURLSession.shared
        switch type {
        case .openAI:
            return OpenAIProvider(apiKey: key, model: resolveModel(.openAI, envKey: "OPENAI_MODEL"), urlSession: session)
        case .gemini:
            return GeminiProvider(apiKey: key, model: resolveModel(.gemini, envKey: "GEMINI_MODEL"), urlSession: session)
        case .grok:
            return GrokProvider(apiKey: key, model: resolveModel(.grok, envKey: "GROK_MODEL"), urlSession: session)
        case .anthropic:
            // Anthropic resolution retains its special case: CONSENSUS_MODEL env
            // var still takes precedence over the per-provider override here, so
            // operators can split per-round Claude from the deciding Claude
            // without touching their strategy.json.
            if let consensus = env["CONSENSUS_MODEL"], !consensus.isEmpty {
                return AnthropicProvider(apiKey: key, model: consensus, urlSession: session)
            }
            return AnthropicProvider(apiKey: key, model: resolveModel(.anthropic, envKey: "ANTHROPIC_MODEL"), urlSession: session)
        case .ollama:
            return nil
        case .openAICompatible:
            // Local OpenAI-compatible servers (LM Studio, Jan, llama.cpp) can't
            // moderate — they're spokes only. The moderator role needs a model
            // we've curated for consensus-synthesis behavior; local models vary
            // too much to hand them that job by default.
            return nil
        }
    }

    /// Build the tiebreaker instance for a `TiebreakerSelection`. Returns nil for
    /// `.sameAsModerator` — the orchestrator interprets nil as "fall back to the
    /// moderator" rather than "no tiebreaker", so callers don't need to special-case
    /// this selection themselves.
    public static func buildTiebreaker(
        for selection: TiebreakerSelection,
        resolveKey: (ProviderType) -> String?,
        models: [ProviderType: String]? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any ReviewProvider)? {
        switch selection {
        case .sameAsModerator:
            return nil
        case .specific(let moderatorSelection):
            return build(for: moderatorSelection, resolveKey: resolveKey, models: models, env: env)
        }
    }
}
