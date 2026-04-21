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
        ollama: OllamaConfig? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [any ReviewProvider] {
        var providers: [any ReviewProvider] = []

        func isExcluded(_ type: ProviderType) -> Bool {
            guard let weights else { return false }
            guard let weight = weights[type] else { return false }
            return weight <= 0
        }

        if !isExcluded(.openAI), let key = resolveKey(.openAI) {
            providers.append(OpenAIProvider(
                apiKey: key,
                model: env["OPENAI_MODEL"] ?? ProviderType.openAI.defaultModel
            ))
        }
        if !isExcluded(.gemini), let key = resolveKey(.gemini) {
            providers.append(GeminiProvider(
                apiKey: key,
                model: env["GEMINI_MODEL"] ?? ProviderType.gemini.defaultModel
            ))
        }
        if !isExcluded(.grok), let key = resolveKey(.grok) {
            providers.append(GrokProvider(
                apiKey: key,
                model: env["GROK_MODEL"] ?? ProviderType.grok.defaultModel
            ))
        }
        if !isExcluded(.anthropic), let key = resolveKey(.anthropic) {
            providers.append(AnthropicProvider(
                apiKey: key,
                model: env["ANTHROPIC_MODEL"] ?? ProviderType.anthropic.defaultModel
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
            if let url = URL(string: endpointString) {
                providers.append(OllamaProvider(model: model, endpoint: url))
            } else {
                providers.append(OllamaProvider(model: model))
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
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any ReviewProvider)? {
        guard let type = selection.providerType else { return nil }
        guard let key = resolveKey(type) else { return nil }

        switch type {
        case .openAI:
            return OpenAIProvider(apiKey: key, model: env["OPENAI_MODEL"] ?? type.defaultModel)
        case .gemini:
            return GeminiProvider(apiKey: key, model: env["GEMINI_MODEL"] ?? type.defaultModel)
        case .grok:
            return GrokProvider(apiKey: key, model: env["GROK_MODEL"] ?? type.defaultModel)
        case .anthropic:
            let model = env["CONSENSUS_MODEL"] ?? env["ANTHROPIC_MODEL"] ?? type.defaultModel
            return AnthropicProvider(apiKey: key, model: model)
        case .ollama:
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
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any ReviewProvider)? {
        switch selection {
        case .sameAsModerator:
            return nil
        case .specific(let moderatorSelection):
            return build(for: moderatorSelection, resolveKey: resolveKey, env: env)
        }
    }
}
