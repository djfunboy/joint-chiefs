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
    /// `OLLAMA_ENABLED=1`. Preserves the ordering used by the pre-refactor callers
    /// (OpenAI, Gemini, Grok, Anthropic, Ollama) so existing tests remain stable.
    public static func buildPanel(
        resolveKey: (ProviderType) -> String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> [any ReviewProvider] {
        var providers: [any ReviewProvider] = []

        if let key = resolveKey(.openAI) {
            providers.append(OpenAIProvider(
                apiKey: key,
                model: env["OPENAI_MODEL"] ?? ProviderType.openAI.defaultModel
            ))
        }
        if let key = resolveKey(.gemini) {
            providers.append(GeminiProvider(
                apiKey: key,
                model: env["GEMINI_MODEL"] ?? ProviderType.gemini.defaultModel
            ))
        }
        if let key = resolveKey(.grok) {
            providers.append(GrokProvider(
                apiKey: key,
                model: env["GROK_MODEL"] ?? ProviderType.grok.defaultModel
            ))
        }
        if let key = resolveKey(.anthropic) {
            providers.append(AnthropicProvider(
                apiKey: key,
                model: env["ANTHROPIC_MODEL"] ?? ProviderType.anthropic.defaultModel
            ))
        }
        if env["OLLAMA_ENABLED"] == "1" {
            providers.append(OllamaProvider(
                model: env["OLLAMA_MODEL"] ?? ProviderType.ollama.defaultModel
            ))
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
