import ArgumentParser
import Foundation
import JointChiefsCore

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List configured LLM providers"
    )

    func run() throws {
        var debaters: [String] = []

        print("Debate panel:")
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            let model = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.4"
            print("  \u{2605} OpenAI: \(model)")
            debaters.append("OpenAI")
        }

        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            let model = ProcessInfo.processInfo.environment["GEMINI_MODEL"] ?? "gemini-3.1-pro-preview"
            print("  \u{2605} Gemini: \(model)")
            debaters.append("Gemini")
        }

        if let key = ProcessInfo.processInfo.environment["GROK_API_KEY"], !key.isEmpty {
            let model = ProcessInfo.processInfo.environment["GROK_MODEL"] ?? "grok-3"
            print("  \u{2605} Grok: \(model)")
            debaters.append("Grok")
        }

        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            let model = ProcessInfo.processInfo.environment["ANTHROPIC_MODEL"] ?? "claude-opus-4-6"
            print("  \u{2605} Claude: \(model) (also deciding model)")
            debaters.append("Claude")
        }

        if ProcessInfo.processInfo.environment["OLLAMA_ENABLED"] == "1" {
            let model = ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "llama3"
            print("  \u{2605} Ollama: \(model) (local)")
            debaters.append("Ollama")
        }

        if debaters.isEmpty {
            print("  (none)")
        }

        print("")
        print("Deciding model (consensus):")
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            let model = ProcessInfo.processInfo.environment["CONSENSUS_MODEL"] ?? "claude-opus-4-6"
            print("  \u{2606} Claude: \(model)")
        } else {
            print("  (code-based fallback — set ANTHROPIC_API_KEY for Claude consensus)")
        }

        if debaters.isEmpty {
            print("")
            print("Set environment variables to configure:")
            print("  OPENAI_API_KEY      — OpenAI (override model: OPENAI_MODEL)")
            print("  GEMINI_API_KEY      — Google Gemini (override model: GEMINI_MODEL)")
            print("  GROK_API_KEY        — xAI Grok (override model: GROK_MODEL)")
            print("  OLLAMA_ENABLED=1    — Local Ollama (override model: OLLAMA_MODEL)")
            print("  ANTHROPIC_API_KEY   — Claude as deciding model (override: CONSENSUS_MODEL)")
        }
    }
}
