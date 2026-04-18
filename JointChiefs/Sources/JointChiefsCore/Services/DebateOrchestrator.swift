import Foundation
import os

// MARK: - DebateOrchestrator

/// Coordinates multi-model code review through parallel initial reviews, structured debate
/// rounds, and consensus synthesis.
///
/// Uses Swift concurrency (`withThrowingTaskGroup`) to run all provider calls in parallel.
/// Gracefully degrades when individual providers fail — only throws if all providers fail.
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
    public init(
        providers: [any ReviewProvider],
        moderator: (any ReviewProvider)? = nil,
        tiebreaker: (any ReviewProvider)? = nil,
        strategy: StrategyConfig = .default
    ) {
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
    ) {
        self.init(
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
    /// - Throws: `OrchestratorError` if no providers are configured or all providers fail.
    public func runReview(
        context: ReviewContext
    ) async throws -> (ConsensusSummary, DebateTranscript) {
        guard !providers.isEmpty else {
            throw OrchestratorError.noProviders
        }

        var transcript = DebateTranscript(
            filePath: context.filePath ?? "unknown",
            goal: context.goal ?? "General code review",
            codeSnippet: context.code
        )

        // Phase 1: Parallel initial reviews
        let initialResponses = try await runInitialReviews(context: context)
        let initialRound = TranscriptRound(
            roundNumber: 0,
            phase: .independent,
            responses: initialResponses
        )
        transcript.rounds.append(initialRound)

        // Phase 2: Debate rounds (hub-and-spoke via moderator)
        // Each round: generals report → Claude synthesizes → consolidated brief sent to next round
        var synthesizedFindings = initialResponses.flatMap { $0.findings }

        for roundNumber in 0..<debateRounds {
            let round = roundNumber + 1

            // Between-round synthesis runs for every consensus mode — it's a
            // prompt-compaction pass, not a decision, so the final mode is irrelevant here.
            if let moderator {
                synthesizedFindings = (try? await ConsensusBuilder.synthesizeRound(
                    findings: synthesizedFindings,
                    code: context.code,
                    goal: context.goal ?? "General code review",
                    moderator: moderator
                )) ?? synthesizedFindings
            }

            let debateResponses = try await runDebateRound(
                code: context.code,
                priorFindings: synthesizedFindings,
                round: round
            )
            let debateRound = TranscriptRound(
                roundNumber: round,
                phase: .debate,
                responses: debateResponses
            )
            transcript.rounds.append(debateRound)

            // Update synthesized findings for next round
            synthesizedFindings = debateResponses.flatMap { $0.findings }

            // Adaptive early stopping: if positions converged, stop debating
            if round >= 2,
               let previousRound = transcript.rounds.dropLast().last,
               Self.checkConvergence(currentRound: debateRound, previousRound: previousRound) {
                logger.info("Debate converged after round \(round) — stopping early")
                break
            }
        }

        // Phase 3: Consensus synthesis
        // Build code-based consensus from the final round, then branch on the
        // configured ConsensusMode to decide whether to filter, include all,
        // or hand off to a deciding LLM.
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

    /// Runs a streaming review that emits events as each phase progresses.
    ///
    /// Use this when you want real-time visibility into the debate.
    /// The stream completes after emitting `.completed` or `.failed`.
    public func runReviewStreaming(context: ReviewContext) -> AsyncStream<ReviewEvent> {
        let providers = self.providers
        let moderator = self.moderator
        let tiebreaker = self.tiebreaker
        let strategy = self.strategy
        let debateRounds = strategy.maxRounds

        return AsyncStream { continuation in
            Task {
                do {
                    guard !providers.isEmpty else {
                        continuation.yield(.failed(error: "No providers configured"))
                        continuation.finish()
                        return
                    }

                    let providerNames = providers.map { "\($0.name) (\($0.model))" }
                    continuation.yield(.sessionStarted(providers: providerNames, debateRounds: debateRounds))

                    var transcript = DebateTranscript(
                        filePath: context.filePath ?? "unknown",
                        goal: context.goal ?? "General code review",
                        codeSnippet: context.code
                    )

                    // Phase 1: Parallel initial reviews with per-provider events
                    var initialResponses: [ProviderReview] = []
                    var errors: [String] = []

                    for provider in providers {
                        continuation.yield(.providerReviewing(name: "\(provider.name) (\(provider.model))"))
                    }

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
                                continuation.yield(.providerReviewed(review: review))
                            case .failure(let error):
                                let message = error.localizedDescription
                                errors.append(message)
                                continuation.yield(.providerFailed(name: named.name, error: message))
                            }
                        }
                    }

                    guard !initialResponses.isEmpty else {
                        continuation.yield(.failed(error: "All providers failed: \(errors.joined(separator: ", "))"))
                        continuation.finish()
                        return
                    }

                    let initialRound = TranscriptRound(roundNumber: 0, phase: .independent, responses: initialResponses)
                    transcript.rounds.append(initialRound)
                    continuation.yield(.initialReviewsComplete(responseCount: initialResponses.count))

                    // Phase 2: Debate rounds (hub-and-spoke via moderator)
                    var synthesizedFindings = initialResponses.flatMap { $0.findings }

                    for roundNumber in 0..<debateRounds {
                        let round = roundNumber + 1

                        // Moderator synthesizes before sending to generals
                        if let moderator {
                            continuation.yield(.moderatorSynthesizing(round: round))
                            if let consolidated = try? await ConsensusBuilder.synthesizeRound(
                                findings: synthesizedFindings,
                                code: context.code,
                                goal: context.goal ?? "General code review",
                                moderator: moderator
                            ) {
                                synthesizedFindings = consolidated
                                continuation.yield(.moderatorSynthesized(findingCount: consolidated.count, round: round))
                            }
                        }

                        continuation.yield(.debateRoundStarting(round: round, totalRounds: debateRounds))

                        let findingsForRound = synthesizedFindings
                        var debateResponses: [ProviderReview] = []

                        await withTaskGroup(of: NamedResult.self) { group in
                            for provider in providers {
                                group.addTask {
                                    let name = "\(provider.name) (\(provider.model))"
                                    do {
                                        let review = try await provider.debate(code: context.code, priorFindings: findingsForRound, round: round)
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
                                    continuation.yield(.providerDebated(review: review, round: round))
                                case .failure(let error):
                                    continuation.yield(.providerFailed(name: named.name, error: error.localizedDescription))
                                }
                            }
                        }

                        let debateRound = TranscriptRound(roundNumber: round, phase: .debate, responses: debateResponses)
                        transcript.rounds.append(debateRound)
                        synthesizedFindings = debateResponses.flatMap { $0.findings }

                        // Adaptive early stopping
                        if round >= 2,
                           let previousRound = transcript.rounds.dropLast().last {
                            let converged = Self.checkConvergence(
                                currentRound: debateRound,
                                previousRound: previousRound
                            )
                            if converged {
                                continuation.yield(.debateConverged(afterRound: round))
                                break
                            }
                        }
                    }

                    // Phase 3: Consensus
                    continuation.yield(.buildingConsensus)
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

                    continuation.yield(.completed(summary: summary, transcript: transcript))
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Supporting Types

    /// Wraps a provider result with the provider's name for event reporting.
    private struct NamedResult: Sendable {
        let name: String
        let result: Result<ProviderReview, Error>
    }

    // MARK: - Private Methods

    /// Runs initial reviews across all providers in parallel with per-provider timeout.
    private func runInitialReviews(
        context: ReviewContext
    ) async throws -> [ProviderReview] {
        var responses: [ProviderReview] = []
        var errors: [String] = []

        await withTaskGroup(of: Result<ProviderReview, Error>.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return .success(try await provider.review(code: context.code, context: context))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let review):
                    responses.append(review)
                case .failure(let error):
                    let message = error.localizedDescription
                    logger.warning("Provider failed during initial review: \(message)")
                    errors.append(message)
                }
            }
        }

        guard !responses.isEmpty else {
            throw OrchestratorError.allProvidersFailed(errors: errors)
        }

        return responses
    }

    /// Runs a single debate round across all providers in parallel.
    private func runDebateRound(
        code: String,
        priorFindings: [Finding],
        round: Int
    ) async throws -> [ProviderReview] {
        var responses: [ProviderReview] = []
        var errors: [String] = []

        await withTaskGroup(of: Result<ProviderReview, Error>.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return .success(try await provider.debate(
                            code: code,
                            priorFindings: priorFindings,
                            round: round
                        ))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let review):
                    responses.append(review)
                case .failure(let error):
                    let message = error.localizedDescription
                    logger.warning("Provider failed during debate round \(round): \(message)")
                    errors.append(message)
                }
            }
        }

        // Graceful degradation: allow debate rounds to continue with partial results.
        // Only the initial review phase requires at least one response.
        return responses
    }

    /// Collects all findings from all rounds in the transcript.
    private func collectFindings(from transcript: DebateTranscript) -> [Finding] {
        transcript.rounds.flatMap { round in
            round.responses.flatMap { $0.findings }
        }
    }

    /// Applies the configured `ConsensusMode` to a code-based summary, optionally invoking
    /// the deciding LLM. Static so both `runReview` (actor-isolated) and `runReviewStreaming`
    /// (Task-captured) can call it without re-deriving the logic.
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
            let total = transcript.rounds.last?.responses.count ?? providers.count
            guard total > 0 else { return codeSummary }
            let threshold = strategy.thresholdPercent
            return ConsensusBuilder.filter(codeSummary) { finding in
                let raised = finding.raisedBy?.count ?? 0
                return Double(raised) / Double(total) >= threshold
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

    /// Runs an async operation with a timeout, returning a Result.
    private static func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        await withTaskGroup(of: Result<T, Error>.self) { group in
            group.addTask {
                do {
                    let value = try await operation()
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return .failure(ProviderError.timeout)
            }

            // First to finish wins; cancel the other
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }
}
