import ArgumentParser
import Foundation
import JointChiefsCore

struct Models: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List configured LLM providers and verify connectivity"
    )

    @Flag(name: .long, help: "Verify each configured provider by pinging its API")
    var test: Bool = false

    // MARK: - Entry

    func run() async throws {
        let slots = ProviderSlot.all
        let hasAnthropic = slots.first(where: { $0.kind == .anthropic })?.isConfigured == true

        print("Joint Chiefs panel")
        print("")

        if test {
            try await runWithTest(slots: slots)
        } else {
            runWithoutTest(slots: slots)
        }

        print("")
        print("Moderator")
        if hasAnthropic {
            let model = ProcessInfo.processInfo.environment["CONSENSUS_MODEL"]
                ?? ProcessInfo.processInfo.environment["ANTHROPIC_MODEL"]
                ?? ProviderType.anthropic.defaultModel
            print("  \(Glyph.star) Claude \(model)")
        } else {
            print("  \(Glyph.warn) code-based fallback — configure Claude via setup app or set ANTHROPIC_API_KEY")
        }

        if !test {
            print("")
            print("Run `jointchiefs models --test` to verify keys actually work.")
        }
    }

    // MARK: - Default (no --test)

    private func runWithoutTest(slots: [ProviderSlot]) {
        for slot in slots {
            printSlotRow(slot, status: nil)
        }
    }

    // MARK: - With --test

    private func runWithTest(slots: [ProviderSlot]) async throws {
        // Probe each configured slot in parallel; record ordered results by slot kind.
        var results: [ProviderSlot.Kind: TestResult] = [:]

        await withTaskGroup(of: (ProviderSlot.Kind, TestResult).self) { group in
            for slot in slots where slot.isConfigured {
                group.addTask {
                    guard let provider = slot.makeProvider() else {
                        return (slot.kind, .skipped)
                    }
                    let start = Date()
                    do {
                        _ = try await provider.testConnection()
                        return (slot.kind, .ok(elapsed: Date().timeIntervalSince(start)))
                    } catch {
                        return (slot.kind, .failed(message: Self.describe(error)))
                    }
                }
            }
            for await (kind, result) in group {
                results[kind] = result
            }
        }

        for slot in slots {
            printSlotRow(slot, status: slot.isConfigured ? results[slot.kind] : nil)
        }

        let configured = slots.filter { $0.isConfigured }
        let passed = configured.filter { results[$0.kind]?.passed == true }.count
        let failed = configured.count - passed
        print("")
        if failed == 0, configured.isEmpty {
            print("No providers configured. Add at least one API key to get started.")
        } else if failed == 0 {
            print("\(passed)/\(configured.count) configured providers passed.")
        } else {
            print("\(passed)/\(configured.count) configured providers passed. Fix the failures before running reviews.")
        }
    }

    // MARK: - Row Printing

    private func printSlotRow(_ slot: ProviderSlot, status: TestResult?) {
        let icon: String
        if slot.isConfigured {
            icon = Glyph.star
        } else if slot.needsMigration {
            icon = Glyph.warn
        } else {
            icon = Glyph.empty
        }
        let name = slot.displayName.padding(toLength: 9, withPad: " ", startingAt: 0)
        let model = (slot.model ?? "").padding(toLength: 28, withPad: " ", startingAt: 0)

        let trailer: String
        if slot.isConfigured {
            switch status {
            case .ok(let elapsed):
                trailer = "\(Glyph.check) ok (\(String(format: "%.1fs", elapsed)))"
            case .failed(let message):
                trailer = "\(Glyph.cross) \(message)"
            case .skipped, nil:
                trailer = "configured"
            }
        } else {
            trailer = slot.unconfiguredHint
        }

        print("  \(icon) \(name) \(model) \(trailer)")
    }

    // MARK: - Error Formatting

    private static func describe(_ error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .authenticationFailed:
                return "authentication failed (check the API key)"
            case .rateLimited(let retryAfter):
                if let retry = retryAfter {
                    return "rate limited (retry after \(Int(retry))s)"
                }
                return "rate limited"
            case .timeout:
                return "timed out"
            case .serverError(let statusCode, _):
                return "server error \(statusCode)"
            case .networkError(let detail):
                return "network error: \(detail)"
            case .malformedResponse(let detail):
                return "malformed response: \(detail)"
            case .missingAPIKey:
                return "missing API key"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Glyphs

    private enum Glyph {
        static let star = "\u{2605}"     // ★ — configured
        static let empty = "\u{25CB}"    // ○ — not configured
        static let check = "\u{2713}"    // ✓ — test passed
        static let cross = "\u{2717}"    // ✗ — test failed
        static let warn = "\u{26A0}\u{FE0F}"  // ⚠️ — warning
    }
}

// MARK: - ProviderSlot

/// Describes a provider slot whether or not it's currently configured.
/// Lets the `models` command always show the full panel of supported providers
/// so new users see the full menu of options instead of only what they've set up.
private struct ProviderSlot: Sendable {
    enum Kind: CaseIterable, Sendable {
        case openai, gemini, grok, anthropic, ollama
    }

    let kind: Kind
    let displayName: String
    let model: String?
    let isConfigured: Bool
    /// True when a key still lives in the old macOS Keychain and hasn't been
    /// migrated into the credential file — so the row reports "open Joint Chiefs
    /// once to migrate" rather than the misleading "not configured".
    let needsMigration: Bool
    let unconfiguredHint: String
    private let providerFactory: @Sendable () -> (any ReviewProvider)?

    init(
        kind: Kind,
        displayName: String,
        model: String?,
        isConfigured: Bool,
        needsMigration: Bool,
        unconfiguredHint: String,
        providerFactory: @escaping @Sendable () -> (any ReviewProvider)?
    ) {
        self.kind = kind
        self.displayName = displayName
        self.model = model
        self.isConfigured = isConfigured
        self.needsMigration = needsMigration
        self.unconfiguredHint = unconfiguredHint
        self.providerFactory = providerFactory
    }

    func makeProvider() -> (any ReviewProvider)? { providerFactory() }

    static var all: [ProviderSlot] { Kind.allCases.map { kind in
        let env = ProcessInfo.processInfo.environment

        switch kind {
        case .openai:
            let resolved = resolveKey(.openAI)
            let model = env["OPENAI_MODEL"] ?? ProviderType.openAI.defaultModel
            return ProviderSlot(
                kind: .openai,
                displayName: "OpenAI",
                model: model,
                isConfigured: resolved.key != nil,
                needsMigration: resolved.needsMigration,
                unconfiguredHint: hint(needsMigration: resolved.needsMigration, envVar: "OPENAI_API_KEY"),
                providerFactory: { resolved.key.map { OpenAIProvider(apiKey: $0, model: model) } }
            )

        case .gemini:
            let resolved = resolveKey(.gemini)
            let model = env["GEMINI_MODEL"] ?? ProviderType.gemini.defaultModel
            return ProviderSlot(
                kind: .gemini,
                displayName: "Gemini",
                model: model,
                isConfigured: resolved.key != nil,
                needsMigration: resolved.needsMigration,
                unconfiguredHint: hint(needsMigration: resolved.needsMigration, envVar: "GEMINI_API_KEY"),
                providerFactory: { resolved.key.map { GeminiProvider(apiKey: $0, model: model) } }
            )

        case .grok:
            let resolved = resolveKey(.grok)
            let model = env["GROK_MODEL"] ?? ProviderType.grok.defaultModel
            return ProviderSlot(
                kind: .grok,
                displayName: "Grok",
                model: model,
                isConfigured: resolved.key != nil,
                needsMigration: resolved.needsMigration,
                unconfiguredHint: hint(needsMigration: resolved.needsMigration, envVar: "GROK_API_KEY"),
                providerFactory: { resolved.key.map { GrokProvider(apiKey: $0, model: model) } }
            )

        case .anthropic:
            let resolved = resolveKey(.anthropic)
            let model = env["ANTHROPIC_MODEL"] ?? ProviderType.anthropic.defaultModel
            return ProviderSlot(
                kind: .anthropic,
                displayName: "Claude",
                model: model,
                isConfigured: resolved.key != nil,
                needsMigration: resolved.needsMigration,
                unconfiguredHint: hint(needsMigration: resolved.needsMigration, envVar: "ANTHROPIC_API_KEY", suffix: " (also the moderator)"),
                providerFactory: { resolved.key.map { AnthropicProvider(apiKey: $0, model: model) } }
            )

        case .ollama:
            let enabled = env["OLLAMA_ENABLED"] == "1"
            let model = env["OLLAMA_MODEL"] ?? ProviderType.ollama.defaultModel
            return ProviderSlot(
                kind: .ollama,
                displayName: "Ollama",
                model: enabled ? model : nil,
                isConfigured: enabled,
                needsMigration: false,
                unconfiguredHint: "disabled — set OLLAMA_ENABLED=1 for local models",
                providerFactory: { enabled ? OllamaProvider(model: model) : nil }
            )
        }
    } }

    /// Resolve a provider's key for the listing.
    ///
    /// Returns the key when available, plus a `needsMigration` flag set when a
    /// key still lives in the old macOS Keychain and hasn't been moved into the
    /// credential file. That case must NOT be reported as "not configured" — it
    /// has a specific fix (open the Joint Chiefs app once, or set the env var).
    /// Any other resolver error stays non-fatal: treated as unconfigured here,
    /// surfaced by `--test`.
    private static func resolveKey(_ provider: ProviderType) -> (key: String?, needsMigration: Bool) {
        do {
            return (try APIKeyResolver.resolve(provider), false)
        } catch APIKeyResolverError.legacyKeysNeedMigration {
            return (nil, true)
        } catch APIKeyResolverError.interactionNotAllowed {
            return (nil, true)
        } catch {
            return (nil, false)
        }
    }

    /// Trailing hint for a non-configured slot. A `needsMigration` slot has a
    /// saved key still in the old macOS Keychain — distinct from a genuinely
    /// missing key.
    private static func hint(needsMigration: Bool, envVar: String, suffix: String = "") -> String {
        needsMigration
            ? "key in old storage — open the Joint Chiefs app once to migrate it, or set \(envVar)"
            : "not configured — add via setup app or set \(envVar)\(suffix)"
    }
}

// MARK: - TestResult

private enum TestResult {
    case ok(elapsed: TimeInterval)
    case failed(message: String)
    case skipped

    var passed: Bool {
        if case .ok = self { return true }
        return false
    }
}
