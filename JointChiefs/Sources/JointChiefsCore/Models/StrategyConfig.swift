import Foundation

/// User-configurable parameters that shape how a debate unfolds. Persisted by the
/// setup app to `~/Library/Application Support/Joint Chiefs/strategy.json` and
/// consumed by the CLI, MCP server, and orchestrator. CLI flags can override
/// individual fields per invocation.
///
/// Defaults match the behavior of the v1 CLI, so strategy changes are purely additive —
/// anyone who never opens the setup app gets the same experience as today.
public struct StrategyConfig: Codable, Sendable, Equatable {

    // MARK: - Moderator

    /// Which provider plays the moderator role — reads anonymized findings each round
    /// and writes the final consensus synthesis. Defaults to Claude.
    public var moderator: ModeratorSelection

    /// Which provider breaks ties if consensus isn't reached after `maxRounds`.
    /// Nil means "same as moderator" (the common case).
    public var tiebreaker: TiebreakerSelection

    // MARK: - Consensus Mode

    /// How findings from the debate are aggregated into the final consensus.
    public var consensus: ConsensusMode

    // MARK: - Debate Shape

    /// Maximum number of debate rounds. Adaptive early-break stops sooner on convergence.
    public var maxRounds: Int

    /// Per-provider request timeout in seconds.
    public var timeoutSeconds: Int

    /// Fraction of providers that must raise a finding for it to survive, when
    /// `consensus == .votingThreshold`. Ignored for other modes. Range: 0.0–1.0.
    public var thresholdPercent: Double

    // MARK: - Per-Provider Weighting

    /// Per-provider weight used in two places:
    ///
    /// 1. **Panel inclusion.** A weight of `0.0` excludes the provider from the spoke
    ///    panel entirely — `ProviderFactory.buildPanel` skips it even if an API key is
    ///    available. Any other value (including missing entries) includes the provider.
    /// 2. **Voting-threshold math.** In `ConsensusMode.votingThreshold`, the survival
    ///    ratio is `sum(weights of providers who raised a finding) / sum(weights of
    ///    all providers that responded in the final round)`. Equal weights reduce
    ///    to the pre-weighting raw-count ratio.
    ///
    /// Missing entries default to `1.0`. Setting this to an empty dictionary yields
    /// the v1 behavior.
    public var providerWeights: [ProviderType: Double]

    // MARK: - Per-Provider Model Selection

    /// Override the default model string for a given provider (e.g. pick
    /// `claude-sonnet-4-6` over `claude-opus-4-6`). Resolution priority in
    /// `ProviderFactory`: `providerModels[type]` > env var (`OPENAI_MODEL`,
    /// `ANTHROPIC_MODEL`, etc.) > `ProviderType.defaultModel`.
    ///
    /// Missing entries fall through to the next tier. Empty-string entries are
    /// treated as missing so users can't accidentally lock a provider into a
    /// blank model.
    public var providerModels: [ProviderType: String]

    // MARK: - Local Models (Ollama)

    /// Configuration for the optional local Ollama general. When disabled, Ollama
    /// is skipped even if the server is reachable. The `OLLAMA_ENABLED` env var
    /// remains a CI override: set to `1` to force-include or `0` to force-exclude,
    /// regardless of this setting.
    public var ollama: OllamaConfig

    // MARK: - Rate Limiting (MCP server only)

    /// Rate limits applied in the MCP server context, to defend against stuck
    /// autonomous-agent retry loops and runaway API costs.
    public var rateLimits: RateLimits

    // MARK: - Defaults

    public static let `default` = StrategyConfig(
        moderator: .claude,
        tiebreaker: .sameAsModerator,
        consensus: .moderatorDecides,
        maxRounds: 5,
        timeoutSeconds: 120,
        thresholdPercent: 0.66,
        providerWeights: [:],
        providerModels: [:],
        ollama: .default,
        rateLimits: .default
    )

    public init(
        moderator: ModeratorSelection = .claude,
        tiebreaker: TiebreakerSelection = .sameAsModerator,
        consensus: ConsensusMode = .moderatorDecides,
        maxRounds: Int = 5,
        timeoutSeconds: Int = 120,
        thresholdPercent: Double = 0.66,
        providerWeights: [ProviderType: Double] = [:],
        providerModels: [ProviderType: String] = [:],
        ollama: OllamaConfig = .default,
        rateLimits: RateLimits = .default
    ) {
        self.moderator = moderator
        self.tiebreaker = tiebreaker
        self.consensus = consensus
        self.maxRounds = maxRounds
        self.timeoutSeconds = timeoutSeconds
        self.thresholdPercent = thresholdPercent
        self.providerWeights = providerWeights
        self.providerModels = providerModels
        self.ollama = ollama
        self.rateLimits = rateLimits
    }

    /// Returns the user-configured model override for a provider, or nil if the
    /// user hasn't set one. Empty strings return nil (treated as "not set").
    /// `ProviderFactory` falls back to env var → default when this returns nil.
    public func model(for provider: ProviderType) -> String? {
        guard let value = providerModels[provider], !value.isEmpty else { return nil }
        return value
    }

    /// Returns the configured weight for a provider, falling back to `1.0` when
    /// no explicit entry is set. A weight of `0.0` signals "exclude from panel."
    public func weight(for provider: ProviderType) -> Double {
        providerWeights[provider] ?? 1.0
    }

    /// True when the provider should be dropped from the panel entirely.
    public func isExcluded(_ provider: ProviderType) -> Bool {
        weight(for: provider) <= 0
    }
}

// MARK: - Codable migration

extension StrategyConfig {
    // Older strategy.json files omit fields added in later revisions. Supply
    // defaults so old configs still decode cleanly.
    private enum CodingKeys: String, CodingKey {
        case moderator, tiebreaker, consensus, maxRounds, timeoutSeconds
        case thresholdPercent, providerWeights, providerModels, ollama, rateLimits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.moderator = try c.decode(ModeratorSelection.self, forKey: .moderator)
        self.tiebreaker = try c.decode(TiebreakerSelection.self, forKey: .tiebreaker)
        self.consensus = try c.decode(ConsensusMode.self, forKey: .consensus)
        self.maxRounds = try c.decode(Int.self, forKey: .maxRounds)
        self.timeoutSeconds = try c.decode(Int.self, forKey: .timeoutSeconds)
        self.thresholdPercent = try c.decodeIfPresent(Double.self, forKey: .thresholdPercent) ?? 0.66
        // providerWeights round-trips as { "openAI": 1.0, "gemini": 0.0, ... } for
        // human readability. Swift's default synthesized Codable encodes enum-keyed
        // dictionaries as flat arrays, which is unreadable in strategy.json.
        let rawWeights = try c.decodeIfPresent([String: Double].self, forKey: .providerWeights) ?? [:]
        var weights: [ProviderType: Double] = [:]
        for (rawKey, value) in rawWeights {
            if let type = ProviderType(rawValue: rawKey) {
                weights[type] = value
            }
        }
        self.providerWeights = weights
        // providerModels: same enum-keyed-dictionary treatment. Missing field
        // in older strategy.json files decodes to an empty dict, which falls
        // through to env var / default resolution — i.e. identical to v1 behavior.
        let rawModels = try c.decodeIfPresent([String: String].self, forKey: .providerModels) ?? [:]
        var models: [ProviderType: String] = [:]
        for (rawKey, value) in rawModels {
            if let type = ProviderType(rawValue: rawKey) {
                models[type] = value
            }
        }
        self.providerModels = models
        self.ollama = try c.decodeIfPresent(OllamaConfig.self, forKey: .ollama) ?? .default
        self.rateLimits = try c.decode(RateLimits.self, forKey: .rateLimits)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(moderator, forKey: .moderator)
        try c.encode(tiebreaker, forKey: .tiebreaker)
        try c.encode(consensus, forKey: .consensus)
        try c.encode(maxRounds, forKey: .maxRounds)
        try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try c.encode(thresholdPercent, forKey: .thresholdPercent)
        // Map to [String: Double] so the on-disk form is a JSON object, not an array.
        var rawWeights: [String: Double] = [:]
        for (type, value) in providerWeights {
            rawWeights[type.rawValue] = value
        }
        try c.encode(rawWeights, forKey: .providerWeights)
        // Same treatment for providerModels.
        var rawModels: [String: String] = [:]
        for (type, value) in providerModels {
            rawModels[type.rawValue] = value
        }
        try c.encode(rawModels, forKey: .providerModels)
        try c.encode(ollama, forKey: .ollama)
        try c.encode(rateLimits, forKey: .rateLimits)
    }
}

// MARK: - OllamaConfig

public struct OllamaConfig: Codable, Sendable, Equatable {
    /// Whether to include Ollama as a spoke in the debate panel.
    public var enabled: Bool
    /// Model identifier to request from Ollama (e.g. `"llama3"`, `"mistral"`, `"qwen2.5-coder"`).
    public var model: String
    /// Base URL for the Ollama server. Defaults to `http://localhost:11434`; set
    /// to a LAN address to point at a shared Ollama host.
    public var endpoint: String

    public static let `default` = OllamaConfig(
        enabled: false,
        model: "llama3",
        endpoint: "http://localhost:11434"
    )

    public init(enabled: Bool = false, model: String = "llama3", endpoint: String = "http://localhost:11434") {
        self.enabled = enabled
        self.model = model
        self.endpoint = endpoint
    }
}

// MARK: - ModeratorSelection

public enum ModeratorSelection: String, Codable, Sendable, CaseIterable {
    case claude
    case openai
    case gemini
    case grok
    /// Code-based fallback — no LLM moderator, final consensus built algorithmically.
    case none

    /// Resolves to the underlying `ProviderType`, or nil for the code-based fallback.
    public var providerType: ProviderType? {
        switch self {
        case .claude: .anthropic
        case .openai: .openAI
        case .gemini: .gemini
        case .grok: .grok
        case .none: nil
        }
    }
}

// MARK: - TiebreakerSelection

public enum TiebreakerSelection: Codable, Sendable, Equatable {
    case sameAsModerator
    case specific(ModeratorSelection)
}

// MARK: - ConsensusMode

public enum ConsensusMode: String, Codable, Sendable, CaseIterable {
    /// Moderator writes the final synthesis, choosing which findings to include based
    /// on the strength of arguments in debate. This is the v1 behavior.
    case moderatorDecides

    /// Only findings raised by a majority of active providers survive to the final output.
    case strictMajority

    /// Every finding raised by any provider is included in the final output,
    /// tagged with agreement level. No filtering.
    case bestOfAll

    /// Findings survive if raised by at least `threshold` fraction of providers.
    /// The threshold itself is carried alongside this case via `thresholdPercent` below.
    case votingThreshold
}

// MARK: - RateLimits

public struct RateLimits: Codable, Sendable, Equatable {
    /// Maximum concurrent review requests in flight per MCP connection.
    public var maxConcurrentReviews: Int

    /// Maximum reviews per rolling one-hour window per MCP connection.
    public var reviewsPerHour: Int

    /// Optional per-day spend cap in USD. Approximated from per-review token counts
    /// and known provider pricing. `nil` means no cap (the v1 default).
    public var dailySpendCapUSD: Double?

    public static let `default` = RateLimits(
        maxConcurrentReviews: 1,
        reviewsPerHour: 30,
        dailySpendCapUSD: nil
    )

    public init(
        maxConcurrentReviews: Int = 1,
        reviewsPerHour: Int = 30,
        dailySpendCapUSD: Double? = nil
    ) {
        self.maxConcurrentReviews = maxConcurrentReviews
        self.reviewsPerHour = reviewsPerHour
        self.dailySpendCapUSD = dailySpendCapUSD
    }
}
