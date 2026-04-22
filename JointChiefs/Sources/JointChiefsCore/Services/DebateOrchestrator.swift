import Foundation
import os

// MARK: - DebateOrchestrator

/// Coordinates multi-model code review through parallel initial reviews, structured debate
/// rounds, and consensus synthesis.
///
/// Uses Swift concurrency (`withTaskGroup`) to run all provider calls in parallel.
/// Gracefully degrades when individual providers fail — only throws if all providers fail
/// during the initial review phase.
///
/// The public surface is two methods, both powered by a shared actor-isolated core:
/// `runReview(context:)` returns the final `(summary, transcript)` tuple directly;
/// `runReviewStreaming(context:)` wraps the same work in an `AsyncStream<ReviewEvent>`
/// so consumers can watch the debate unfold in real time. Both observe the same
/// cancellation, failure, and convergence semantics.
public actor DebateOrchestrator {

    // MARK: - Private Properties

    private let providers: [any ReviewProvider]
    private let moderator: (any ReviewProvider)?
    private let tiebreaker: (any ReviewProvider)?
    private let strategy: StrategyConfig
    private let logger = Logger(subsystem: "com.jointchiefs", category: "DebateOrchestrator")

    private var debateRounds: Int { strategy.maxRounds }
    private var timeoutSeconds: Int { strategy.timeoutSeconds }

    // MARK: - Init

    /// Primary initializer. Takes an explicit moderator (between-round synthesis and,
    /// when no tiebreaker is supplied, the final decider in `.moderatorDecides` mode),
    /// an optional tiebreaker that overrides the moderator for the final decision,
    /// and a `StrategyConfig` that governs rounds, timeout, and consensus mode.
    ///
    /// Pass `moderator: nil` to run without any LLM-based synthesis — the orchestrator
    /// falls back to code-based consensus in every mode.
    ///
    /// - Throws: `OrchestratorError.invalidConfiguration` if `strategy.maxRounds` is
    ///   negative. Zero is accepted (debate phase is skipped entirely).
    public init(
        providers: [any ReviewProvider],
        moderator: (any ReviewProvider)? = nil,
        tiebreaker: (any ReviewProvider)? = nil,
        strategy: StrategyConfig = .default
    ) throws {
        guard strategy.maxRounds >= 0 else {
            throw OrchestratorError.invalidConfiguration(
                reason: "maxRounds must be >= 0, got \(strategy.maxRounds)"
            )
        }
        self.providers = providers
        self.moderator = moderator
        self.tiebreaker = tiebreaker
        self.strategy = strategy
    }

    /// Back-compat initializer preserving the pre-StrategyConfig signature. Used by
    /// existing tests and any external callers that haven't migrated yet. Internally
    /// delegates to the primary init with a synthesized strategy.
    public init(
        providers: [any ReviewProvider],
        consensusProvider: (any ReviewProvider)? = nil,
        debateRounds: Int = 5,
        timeoutSeconds: Int = 120
    ) throws {
        try self.init(
            providers: providers,
            moderator: consensusProvider,
            tiebreaker: nil,
            strategy: StrategyConfig(
                maxRounds: debateRounds,
                timeoutSeconds: timeoutSeconds
            )
        )
    }

    // MARK: - Public Methods

    /// Runs a full multi-model review: parallel initial reviews, debate rounds, and consensus.
    ///
    /// - Parameter context: The review context containing code, file path, and goal.
    /// - Returns: A tuple of the consensus summary and the full debate transcript.
    /// - Throws: `OrchestratorError` if no providers are configured or all providers fail
    ///   during the initial review phase.
    public func runReview(
        context: ReviewContext
    ) async throws -> (ConsensusSummary, DebateTranscript) {
        try await runReviewCore(context: context, sink: { _ in })
    }

    /// Runs a streaming review that emits events as each phase progresses.
    ///
    /// Use this when you want real-time visibility into the debate. The stream
    /// completes after emitting `.completed` or `.failed`.
    ///
    /// Cancellation: if the consumer stops iterating (e.g. CLI Ctrl-C breaks out
    /// of `for await ...`), the underlying work Task is cancelled via
    /// `continuation.onTermination`. `URLSession.bytes(for:)` and `TaskGroup`
    /// both honor cooperative cancellation, so in-flight HTTP streams are torn
    /// down and spoke requests stop issuing.
    public func runReviewStreaming(context: ReviewContext) -> AsyncStream<ReviewEvent> {
        AsyncStream { continuation in
            let work = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    let sink: @Sendable (ReviewEvent) -> Void = { event in
                        continuation.yield(event)
                    }
                    let (summary, transcript) = try await self.runReviewCore(
                        context: context,
                        sink: sink
                    )
                    continuation.yield(.completed(summary: summary, transcript: transcript))
                } catch is CancellationError {
                    // Consumer stopped iterating — stay silent.
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.failed(error: error.localizedDescription))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                work.cancel()
            }
        }
    }

    // MARK: - Shared Core

    /// Actor-isolated implementation shared by both `runReview` and `runReviewStreaming`.
    /// Emits progress events through `sink`; the non-streaming path passes a no-op sink
    /// and discards them. Throws typed `OrchestratorError` on unrecoverable failure
    /// (no providers, every provider failed in the initial round) so callers can branch
    /// on the error type.
    private func runReviewCore(
        context: ReviewContext,
        sink: @escaping @Sendable (ReviewEvent) -> Void
    ) async throws -> (ConsensusSummary, DebateTranscript) {
        guard !providers.isEmpty else {
            throw OrchestratorError.noProviders
        }

        let providerNames = providers.map { "\($0.name) (\($0.model))" }
        sink(.sessionStarted(providers: providerNames, debateRounds: debateRounds))

        var transcript = DebateTranscript(
            filePath: context.filePath ?? "unknown",
            goal: context.goal ?? "General code review",
            codeSnippet: context.code
        )

        // Phase 1: Parallel initial reviews
        for provider in providers {
            sink(.providerReviewing(name: "\(provider.name) (\(provider.model))"))
        }

        var initialResponses: [ProviderReview] = []
        var initialErrors: [String] = []

        await withTaskGroup(of: NamedResult.self) { group in
            for provider in providers {
                group.addTask {
                    let name = "\(provider.name) (\(provider.model))"
                    do {
                        let review = try await provider.review(code: context.code, context: context)
                        return NamedResult(name: name, result: .success(review))
                    } catch {
                        return NamedResult(name: name, result: .failure(error))
                    }
                }
            }
            for await named in group {
                switch named.result {
                case .success(let review):
                    initialResponses.append(review)
                    sink(.providerReviewed(review: review))
                case .failure(let error):
                    let message = error.localizedDescription
                    logger.warning("Provider failed during initial review: \(message)")
                    initialErrors.append(message)
                    sink(.providerFailed(name: named.name, error: message))
                }
            }
        }

        guard !initialResponses.isEmpty else {
            throw OrchestratorError.allProvidersFailed(errors: initialErrors)
        }

        let initialRound = TranscriptRound(
            roundNumber: 0,
            phase: .independent,
            responses: initialResponses
        )
        transcript.rounds.append(initialRound)
        sink(.initialReviewsComplete(responseCount: initialResponses.count))

        // Phase 2: Debate rounds (hub-and-spoke via moderator)
        var synthesizedFindings = initialResponses.flatMap { $0.findings }

        for roundNumber in 0..<debateRounds {
            let round = roundNumber + 1

            // Between-round synthesis runs for every consensus mode — it's a
            // prompt-compaction pass, not a decision, so the final mode is irrelevant here.
            if let moderator {
                sink(.moderatorSynthesizing(round: round))
                if let consolidated = try? await ConsensusBuilder.synthesizeRound(
                    findings: synthesizedFindings,
                    code: context.code,
                    goal: context.goal ?? "General code review",
                    moderator: moderator
                ) {
                    synthesizedFindings = consolidated
                    sink(.moderatorSynthesized(findingCount: consolidated.count, round: round))
                }
            }

            sink(.debateRoundStarting(round: round, totalRounds: debateRounds))

            let findingsForRound = synthesizedFindings
            var debateResponses: [ProviderReview] = []

            await withTaskGroup(of: NamedResult.self) { group in
                for provider in providers {
                    group.addTask {
                        let name = "\(provider.name) (\(provider.model))"
                        do {
                            let review = try await provider.debate(
                                code: context.code,
                                priorFindings: findingsForRound,
                                round: round
                            )
                            return NamedResult(name: name, result: .success(review))
                        } catch {
                            return NamedResult(name: name, result: .failure(error))
                        }
                    }
                }
                for await named in group {
                    switch named.result {
                    case .success(let review):
                        debateResponses.append(review)
                        sink(.providerDebated(review: review, round: round))
                    case .failure(let error):
                        let message = error.localizedDescription
                        logger.warning("Provider failed during debate round \(round): \(message)")
                        sink(.providerFailed(name: named.name, error: message))
                    }
                }
            }

            let debateRound = TranscriptRound(
                roundNumber: round,
                phase: .debate,
                responses: debateResponses
            )
            transcript.rounds.append(debateRound)
            synthesizedFindings = debateResponses.flatMap { $0.findings }

            // If every provider failed this round, there is no new signal to debate
            // and nothing for convergence detection to read. Stop rather than spin
            // up another empty round that will likely fail the same way.
            if debateResponses.isEmpty {
                logger.warning("Debate round \(round) produced no responses — breaking early")
                break
            }

            // Adaptive early stopping: if positions converged, stop debating.
            if round >= 2,
               let previousRound = transcript.rounds.dropLast().last,
               Self.checkConvergence(currentRound: debateRound, previousRound: previousRound) {
                sink(.debateConverged(afterRound: round))
                break
            }
        }

        // Phase 3: Consensus synthesis
        sink(.buildingConsensus)
        let codeSummary = ConsensusBuilder.synthesize(
            transcript: transcript,
            providers: providers
        )

        let summary = try await Self.applyConsensusMode(
            codeSummary: codeSummary,
            transcript: transcript,
            providers: providers,
            moderator: moderator,
            tiebreaker: tiebreaker,
            strategy: strategy
        )
        transcript.consensusSummary = summary
        transcript.status = .completed

        return (summary, transcript)
    }

    // MARK: - Supporting Types

    /// Wraps a provider result with the provider's name for event reporting.
    private struct NamedResult: Sendable {
        let name: String
        let result: Result<ProviderReview, Error>
    }

    // MARK: - Private Helpers

    /// Applies the configured `ConsensusMode` to a code-based summary, optionally invoking
    /// the deciding LLM. Static so the function can be invoked from the non-isolated
    /// `Task` spawned inside `runReviewStreaming` without re-deriving isolation.
    ///
    /// - `.moderatorDecides` — if any finding is split/solo and a decider exists
    ///   (`tiebreaker ?? moderator`), hand the transcript to that model. Otherwise
    ///   return the code-based summary unchanged.
    /// - `.strictMajority` — drop every finding whose agreement is not unanimous
    ///   or majority. No LLM call.
    /// - `.bestOfAll` — return the code-based summary unchanged (it already
    ///   includes every finding at every agreement level).
    /// - `.votingThreshold` — drop findings whose raised-by ratio falls below
    ///   `strategy.thresholdPercent`. Denominator is the number of providers that
    ///   responded in the final round (matches how `AgreementLevel` is computed).
    private static func applyConsensusMode(
        codeSummary: ConsensusSummary,
        transcript: DebateTranscript,
        providers: [any ReviewProvider],
        moderator: (any ReviewProvider)?,
        tiebreaker: (any ReviewProvider)?,
        strategy: StrategyConfig
    ) async throws -> ConsensusSummary {
        switch strategy.consensus {
        case .moderatorDecides:
            let decider = tiebreaker ?? moderator
            let hasSplits = codeSummary.findings.contains {
                $0.agreement == .split || $0.agreement == .solo
            }
            guard hasSplits, let decider else {
                return codeSummary
            }
            return try await ConsensusBuilder.synthesizeWithModel(
                transcript: transcript,
                providers: providers,
                decidingModel: decider,
                timeoutSeconds: strategy.timeoutSeconds
            )

        case .strictMajority:
            return ConsensusBuilder.filter(codeSummary) {
                $0.agreement == .unanimous || $0.agreement == .majority
            }

        case .bestOfAll:
            return codeSummary

        case .votingThreshold:
            // Weight lookup: map "Provider (model)" label to the provider's weight.
            // Labels mirror how ConsensusBuilder attaches `raisedBy` — keep in sync
            // with `ConsensusBuilder.synthesize` if that formatting ever changes.
            var weightByLabel: [String: Double] = [:]
            for provider in providers {
                let label = "\(provider.name) (\(provider.model))"
                weightByLabel[label] = strategy.weight(for: provider.providerType)
            }
            let respondedLabels: [String] = transcript.rounds.last?.responses.map {
                "\($0.providerName) (\($0.model))"
            } ?? providers.map { "\($0.name) (\($0.model))" }
            let totalWeight = respondedLabels.reduce(0.0) { acc, label in
                acc + (weightByLabel[label] ?? 1.0)
            }
            guard totalWeight > 0 else { return codeSummary }
            let threshold = strategy.thresholdPercent
            return ConsensusBuilder.filter(codeSummary) { finding in
                let raisedWeight = (finding.raisedBy ?? []).reduce(0.0) { acc, label in
                    acc + (weightByLabel[label] ?? 1.0)
                }
                return raisedWeight / totalWeight >= threshold
            }
        }
    }

    /// Checks whether debate has converged by comparing findings between two consecutive rounds.
    ///
    /// Convergence is detected when the set of finding titles is substantially the same and
    /// severity distribution hasn't shifted. Based on MAD research showing that forcing debate
    /// when models already agree hurts quality.
    ///
    /// - Parameters:
    ///   - currentRound: The round that just completed.
    ///   - previousRound: The round before it.
    /// - Returns: `true` if positions have converged and debate can stop early.
    private static func checkConvergence(currentRound: TranscriptRound, previousRound: TranscriptRound) -> Bool {
        let currentFindings = currentRound.responses.flatMap { $0.findings }
        let previousFindings = previousRound.responses.flatMap { $0.findings }

        // Finding count must be within 1 to indicate stability
        guard abs(currentFindings.count - previousFindings.count) <= 1 else {
            return false
        }

        let currentTitles = Set(currentFindings.map { $0.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        let previousTitles = Set(previousFindings.map { $0.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })

        // At least 70% of current titles must have appeared in the previous round
        guard !currentTitles.isEmpty else {
            // Both rounds empty counts as converged
            return previousTitles.isEmpty
        }

        let overlapCount = currentTitles.intersection(previousTitles).count
        let overlapRatio = Double(overlapCount) / Double(currentTitles.count)
        guard overlapRatio >= 0.7 else {
            return false
        }

        // Severity distribution must not have shifted
        let currentSeverities = currentFindings.map { $0.severity }.sorted()
        let previousSeverities = previousFindings.map { $0.severity }.sorted()

        return currentSeverities == previousSeverities
    }
}
