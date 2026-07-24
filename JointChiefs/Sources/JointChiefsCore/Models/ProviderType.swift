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
        case .openAI: "gpt-5.6-sol"
        case .anthropic: "claude-fable-5"
        case .gemini: "gemini-3.6-flash"
        case .grok: "grok-4.5"
        case .ollama: "llama3"
        case .openAICompatible: ""
        }
    }

    /// Curated models per provider — flagship, fast, older flagship,
    /// multimodal/specialized, and a budget option where applicable. First
    /// entry always matches `defaultModel` so the picker opens with the
    /// shipped default selected. Users who need a model outside this list
    /// can still override via env var (OPENAI_MODEL, etc.).
    ///
    /// Keep lists short and opinionated. Stale entries are worse than missing
    /// entries for a setup-app UX.
    ///
    /// Snapshot verified against each provider's live models endpoint on
    /// 2026-07-24 — every id below resolved via its get-model endpoint.
    public var availableModels: [String] {
        switch self {
        case .openAI:
            return [
                "gpt-5.6-sol",    // flagship (default) — GPT-5.6 family
                "gpt-5.6-terra",  // balanced mid-tier
                "gpt-5.5",        // prior flagship
                "gpt-5.6-luna",   // fast + cheap
                "gpt-5.3-codex"   // coding-specialized (newest codex; no 5.6-codex as of 2026-07-22)
            ]
        case .anthropic:
            return [
                "claude-fable-5",                // flagship (default — moderator)
                "claude-opus-5",                 // newest Opus flagship
                "claude-opus-4-8",               // prior Opus flagship (legacy)
                "claude-opus-4-7",               // older Opus flagship
                "claude-sonnet-5",               // newest Sonnet (Claude 5 family)
                "claude-sonnet-4-6",             // balanced
                "claude-haiku-4-5-20251001"      // fast + cheap
            ]
        case .gemini:
            return [
                "gemini-3.6-flash",            // latest agentic/coding default
                "gemini-3.5-flash",            // prior flash
                "gemini-3.1-pro-preview",      // pro-tier preview
                "gemini-3.1-flash-lite"        // fast / cheap (GA)
            ]
        case .grok:
            // xAI chat models from live /v1/models on 2026-07-22.
            // grok-imagine-* are image/video models, not chat-capable.
            return [
                "grok-4.5",                     // flagship (default)
                "grok-4.3",                     // prior flagship
                "grok-4.20-0309-reasoning",     // prior reasoning model
                "grok-4.20-0309-non-reasoning"  // prior fast model
            ]
        case .ollama:
            return []
        case .openAICompatible:
            // Driven by the user's local server's /v1/models response at runtime.
            return []
        }
    }
}
