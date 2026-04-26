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
        case .anthropic: "claude-opus-4-7"
        case .gemini: "gemini-3.1-pro-preview"
        case .grok: "grok-4-0709"
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
    public var availableModels: [String] {
        switch self {
        case .openAI:
            return [
                "gpt-5.5",        // flagship (default) — released 2026-04-23
                "gpt-5.5-pro",    // pro-tier reasoning for hard problems
                "gpt-5.4",        // prior flagship
                "gpt-5.4-mini",   // fast + cheap
                "gpt-5.3-codex"   // coding-specialized (no 5.5-codex variant yet)
            ]
        case .anthropic:
            return [
                "claude-opus-4-7",               // flagship (default — moderator)
                "claude-opus-4-6",               // prior flagship
                "claude-sonnet-4-6",             // balanced
                "claude-haiku-4-5-20251001",     // fast + cheap
                "claude-3-7-sonnet-latest"       // prior-gen fallback
            ]
        case .gemini:
            return [
                "gemini-3.1-pro-preview",   // flagship (default)
                "gemini-2.5-pro",           // prior flagship
                "gemini-2.5-flash",         // fast
                "gemini-2.5-flash-lite",    // budget fast
                "gemini-2.0-flash"          // older gen
            ]
        case .grok:
            return [
                "grok-4-0709",                  // flagship (default) — base GA grok-4
                "grok-4.20-0309-reasoning",     // newest reasoning-tuned snapshot
                "grok-4-fast-reasoning",        // fast + reasoning
                "grok-code-fast-1",             // coding-specialized
                "grok-3"                        // prior-gen fallback
            ]
        case .ollama:
            return []
        case .openAICompatible:
            // Driven by the user's local server's /v1/models response at runtime.
            return []
        }
    }
}
