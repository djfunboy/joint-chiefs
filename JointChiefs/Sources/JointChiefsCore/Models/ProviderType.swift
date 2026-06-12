import Foundation

public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case openAI, anthropic, gemini, grok, ollama, openAICompatible

    public var defaultEndpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .grok: "https://api.x.ai/v1"
        case .ollama: "http://localhost:11434"
        case .openAICompatible: "http://localhost:1234/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-5.5"
        case .anthropic: "claude-fable-5"
        case .gemini: "gemini-3.5-flash"
        case .grok: "grok-4.3"
        case .ollama: "llama3"
        case .openAICompatible: ""
        }
    }

    /// Top 5 curated models per provider — flagship, fast, older flagship,
    /// multimodal/specialized, and a budget option where applicable. First
    /// entry always matches `defaultModel` so the picker opens with the
    /// shipped default selected. Users who need a model outside this list
    /// can still override via env var (OPENAI_MODEL, etc.).
    ///
    /// Keep lists short and opinionated. Stale entries are worse than missing
    /// entries for a setup-app UX.
    ///
    /// Snapshot verified against each provider's live models endpoint on
    /// 2026-06-12 — every id below resolved via its get-model endpoint.
    public var availableModels: [String] {
        switch self {
        case .openAI:
            return [
                "gpt-5.5",        // flagship (default) — released 2026-04-23
                "gpt-5.5-pro",    // pro-tier reasoning for hard problems
                "gpt-5.4",        // prior flagship
                "gpt-5.4-mini",   // fast + cheap
                "gpt-5.3-codex"   // coding-specialized (newest codex; no 5.4/5.5-codex as of 2026-06-12)
            ]
        case .anthropic:
            return [
                "claude-fable-5",                // flagship (default — moderator)
                "claude-opus-4-8",               // prior flagship
                "claude-opus-4-7",               // older flagship
                "claude-sonnet-4-6",             // balanced
                "claude-haiku-4-5-20251001"      // fast + cheap
            ]
        case .gemini:
            return [
                "gemini-3.5-flash",            // latest agentic/coding default
                "gemini-3.1-pro-preview",      // prior flagship
                "gemini-2.5-pro",              // prior-gen flagship
                "gemini-3.1-flash-lite"        // fast / cheap (GA)
            ]
        case .grok:
            // xAI's currently-available chat models, verified against the live
            // /v1/models endpoint on 2026-06-12. grok-4-* and grok-3 retired
            // 2026-05-15 and no longer resolve — do not re-add them.
            // grok-imagine-* are image/video models, not chat-capable.
            return [
                "grok-4.3",                     // flagship (default)
                "grok-4.20-0309-reasoning",     // prior reasoning model
                "grok-4.20-0309-non-reasoning", // prior fast model
                "grok-4.20-multi-agent-0309"    // multi-agent variant
            ]
        case .ollama:
            return []
        case .openAICompatible:
            // Driven by the user's local server's /v1/models response at runtime.
            return []
        }
    }
}
