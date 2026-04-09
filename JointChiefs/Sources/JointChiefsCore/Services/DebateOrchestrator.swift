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
    private let consensusProvider: (any ReviewProvider)?
    private let debateRounds: Int
    private let timeoutSeconds: Int
    private let logger = Logger(subsystem: "com.jointchiefs", category: "DebateOrchestrator")

    // MARK: - Init

    public init(
        providers: [any ReviewProvider],
        consensusProvider: (any ReviewProvider)? = nil,
        debateRounds: Int = 5,
        timeoutSeconds: Int = 120
    ) {
        self.providers = providers
        self.consensusProvider = consensusProvider
        self.debateRounds = debateRounds
        self.timeoutSeconds = timeoutSeconds
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

            // If we have a moderator, synthesize before sending to generals
            if let moderator = consensusProvider {
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
        // Build consensus from the final round. If findings are still split,
        // escalate to the deciding model (Claude) as tiebreaker.
        let codeSummary = ConsensusBuilder.synthesize(
            transcript: transcript,
            providers: providers
        )

        let summary: ConsensusSummary
        let hasSplits = codeSummary.findings.contains { $0.agreement == .split || $0.agreement == .solo }
        if hasSplits, let decider = consensusProvider {
            summary = try await ConsensusBuilder.synthesizeWithModel(
                transcript: transcript,
                providers: providers,
                decidingModel: decider,
                timeoutSeconds: timeoutSeconds
            )
        } else {
            summary = codeSummary
        }
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
        let consensusProvider = self.consensusProvider
        let debateRounds = self.debateRounds
        let timeoutSeconds = self.timeoutSeconds

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
                        if let moderator = consensusProvider {
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
                    let codeSummary = ConsensusBuilder.synthesize(
                        transcript: transcript,
                        providers: providers
                    )

                    let hasSplits = codeSummary.findings.contains { $0.agreement == .split || $0.agreement == .solo }
                    let summary: ConsensusSummary
                    if hasSplits, let decider = consensusProvider {
                        continuation.yield(.buildingConsensus)
                        summary = try await ConsensusBuilder.synthesizeWithModel(
                            transcript: transcript,
                            providers: providers,
                            decidingModel: decider,
                            timeoutSeconds: timeoutSeconds
                        )
                    } else {
                        continuation.yield(.buildingConsensus)
                        summary = codeSummary
                    }
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
