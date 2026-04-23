import Foundation

public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case openAI, anthropic, gemini, grok, ollama

    public var defaultEndpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .grok: "https://api.x.ai/v1"
        case .ollama: "http://localhost:11434"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-5.4"
        case .anthropic: "claude-opus-4-6"
        case .gemini: "gemini-3.1-pro-preview"
        case .grok: "grok-3"
        case .ollama: "llama3"
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
                "gpt-5.4",        // flagship (default)
                "gpt-5.4-mini",   // fast + cheap
                "gpt-4.1",        // prior flagship, still strong
                "gpt-4o",         // multimodal
                "gpt-4o-mini"     // budget multimodal
            ]
        case .anthropic:
            return [
                "claude-opus-4-6",               // flagship (default — moderator)
                "claude-opus-4-7",               // newest flagship
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
                "grok-3",         // flagship (default)
                "grok-3-mini",    // fast
                "grok-2",         // prior flagship
                "grok-2-mini",    // prior fast
                "grok-beta"       // experimental
            ]
        case .ollama:
            return []
        }
    }
}
