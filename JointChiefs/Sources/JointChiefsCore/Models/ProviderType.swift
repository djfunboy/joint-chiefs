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
}
