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
        rateLimits: .default
    )

    public init(
        moderator: ModeratorSelection = .claude,
        tiebreaker: TiebreakerSelection = .sameAsModerator,
        consensus: ConsensusMode = .moderatorDecides,
        maxRounds: Int = 5,
        timeoutSeconds: Int = 120,
        thresholdPercent: Double = 0.66,
        rateLimits: RateLimits = .default
    ) {
        self.moderator = moderator
        self.tiebreaker = tiebreaker
        self.consensus = consensus
        self.maxRounds = maxRounds
        self.timeoutSeconds = timeoutSeconds
        self.thresholdPercent = thresholdPercent
        self.rateLimits = rateLimits
    }
}

// MARK: - Codable migration

extension StrategyConfig {
    // Older strategy.json files (written before thresholdPercent was added) omit
    // the field. Supply the default so old configs still decode cleanly.
    private enum CodingKeys: String, CodingKey {
        case moderator, tiebreaker, consensus, maxRounds, timeoutSeconds
        case thresholdPercent, rateLimits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.moderator = try c.decode(ModeratorSelection.self, forKey: .moderator)
        self.tiebreaker = try c.decode(TiebreakerSelection.self, forKey: .tiebreaker)
        self.consensus = try c.decode(ConsensusMode.self, forKey: .consensus)
        self.maxRounds = try c.decode(Int.self, forKey: .maxRounds)
        self.timeoutSeconds = try c.decode(Int.self, forKey: .timeoutSeconds)
        self.thresholdPercent = try c.decodeIfPresent(Double.self, forKey: .thresholdPercent) ?? 0.66
        self.rateLimits = try c.decode(RateLimits.self, forKey: .rateLimits)
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
