import Foundation

/// Events emitted during a streaming review, allowing callers to display progress in real-time.
public enum ReviewEvent: Sendable {
    /// The review session is starting.
    case sessionStarted(providers: [String], debateRounds: Int)

    /// A provider has begun its initial independent review.
    case providerReviewing(name: String)

    /// A provider completed its initial review.
    case providerReviewed(review: ProviderReview)

    /// A provider failed during review or debate.
    case providerFailed(name: String, error: String)

    /// All initial reviews are in. Debate is about to begin.
    case initialReviewsComplete(responseCount: Int)

    /// A debate round is starting.
    case debateRoundStarting(round: Int, totalRounds: Int)

    /// A provider has responded in a debate round.
    case providerDebated(review: ProviderReview, round: Int)

    /// Claude is synthesizing findings between rounds.
    case moderatorSynthesizing(round: Int)

    /// Claude's synthesis for this round.
    case moderatorSynthesized(findingCount: Int, round: Int)

    /// Debate converged early — positions stopped changing.
    case debateConverged(afterRound: Int)

    /// Debate rounds are complete. Building consensus.
    case buildingConsensus

    /// The review is complete.
    case completed(summary: ConsensusSummary, transcript: DebateTranscript)

    /// The review failed.
    case failed(error: String)
}
