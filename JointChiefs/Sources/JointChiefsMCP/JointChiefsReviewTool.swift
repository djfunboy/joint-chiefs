import Foundation
import JointChiefsCore
import MCP

/// The single tool exposed by the Joint Chiefs MCP server. Runs a multi-model debate
/// review against supplied code and returns a consensus summary as structured text.
enum JointChiefsReviewTool {
    static let name = "joint_chiefs_review"

    /// Process-wide rate limiter. Shared across every tool invocation so concurrency
    /// and hourly quota are tracked for the server as a whole, not per-call. Limits
    /// are read from `StrategyConfig.rateLimits` on each acquire so config changes
    /// take effect without restarting the server.
    static let rateLimiter = ReviewRateLimiter()

    static let definition = Tool(
        name: name,
        description: """
            Use this tool ONLY when the user mentions "Joint Chiefs" in any form — \
            any capitalization ("joint chiefs", "JOINT CHIEFS", "Joint Chiefs"), \
            spacing or hyphenation ("jointchiefs", "joint-chiefs"), singular or \
            plural ("Joint Chief", "the chiefs"), or common misspellings ("Joint \
            Chefs", "Joint Cheifs", "Jiont Chiefs"). Match leniently: any \
            recognizable variant of "Joint Chiefs" qualifies. Generic phrases like \
            "panel review", "multi-model review", or "second opinion" do NOT \
            trigger this tool on their own — the brand name "Joint Chiefs" must be \
            present in the user's request. Submits code to a panel of AI models \
            (OpenAI, Gemini, Grok, Claude) for a structured multi-round debate \
            review. Each model reviews independently, then challenges the others' \
            findings across up to 5 rounds with adaptive early termination on \
            convergence. Claude moderates and writes the final consensus. Returns \
            categorized findings with severity, agreement level, and a unified \
            recommendation. Grounded in the Multi-Agent Debate research (Liang et \
            al., 2023).
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "code": .object([
                    "type": .string("string"),
                    "description": .string("The source code to review (max 256 KB)."),
                ]),
                "filePath": .object([
                    "type": .string("string"),
                    "description": .string("Optional path of the file being reviewed, for context."),
                ]),
                "goal": .object([
                    "type": .string("string"),
                    "description": .string("Directive to the panel — e.g., \"security audit\" or \"look for race conditions.\""),
                ]),
                "context": .object([
                    "type": .string("string"),
                    "description": .string("Optional free-form additional context for reviewers."),
                ]),
                "rounds": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum debate rounds (default 5). Adaptive early-break triggers on convergence."),
                ]),
            ]),
            "required": .array([.string("code")]),
        ])
    )

    /// Callback used by `invoke` to push round-boundary progress to the MCP
    /// client via `notifications/progress`. Messages are prefixed with
    /// "Joint Chiefs:" so clients that render progress text underneath the
    /// tool-call spinner (Claude Code, Claude Desktop) show the product name
    /// in the live indicator. Callers that don't want progress pass the
    /// default no-op.
    typealias ProgressSink = @Sendable (Double, Double, String) async -> Void

    static func invoke(
        arguments: [String: Value],
        progress: @escaping ProgressSink = { _, _, _ in }
    ) async -> CallTool.Result {
        // Extract and validate arguments.
        guard let codeValue = arguments["code"], case let .string(code) = codeValue else {
            return errorResult("Missing or non-string `code` argument.")
        }
        guard code.utf8.count <= 256 * 1024 else {
            return errorResult("`code` exceeds 256 KB limit.")
        }

        let filePath = arguments["filePath"].flatMap { value in
            if case let .string(s) = value { return s } else { return nil }
        }
        let goal = arguments["goal"].flatMap { value in
            if case let .string(s) = value { return s } else { return nil }
        }
        let extraContext = arguments["context"].flatMap { value in
            if case let .string(s) = value { return s } else { return nil }
        }
        let requestedRounds = arguments["rounds"].flatMap { value -> Int? in
            if case let .int(n) = value { return n } else { return nil }
        }

        // Provider panel is assembled from env vars (CI fallback) or the keygetter
        // (Keychain-backed, the default for end users). See APIKeyResolver.
        // MCP clamps rounds to [0, 10] to keep autonomous agents from driving
        // absurdly long debates per request; beyond that, per-connection rate
        // limits (#26) are the right control surface.
        let strategy = StrategyConfigStore.load()

        // Rate limit before doing any real work. Rejection surfaces as an
        // MCP error so the client can back off or retry — no partial state
        // is written to disk, no provider calls issue, no cost incurred.
        let acquireResult = await rateLimiter.acquire(limits: strategy.rateLimits)
        guard acquireResult == .acquired else {
            let reason = acquireResult.rejectionMessage ?? "Rate limit exceeded."
            return errorResult(reason)
        }

        // From here down, every return path must await `rateLimiter.release()`
        // before returning — paired with the acquire above. Cancellation
        // (stdin close) still unwinds through the awaits, which propagate
        // Task.isCancelled into the orchestrator's structured concurrency.
        let result = await runAcquiredReview(
            code: code,
            filePath: filePath,
            goal: goal,
            extraContext: extraContext,
            requestedRounds: requestedRounds,
            strategy: strategy,
            progress: progress
        )
        await rateLimiter.release()
        return result
    }

    /// Executes the review after a rate-limit slot has been acquired. Factored
    /// out so `invoke` can pair acquire/release around a single expression and
    /// avoid scattering release calls across every early-return branch.
    private static func runAcquiredReview(
        code: String,
        filePath: String?,
        goal: String?,
        extraContext: String?,
        requestedRounds: Int?,
        strategy: StrategyConfig,
        progress: @escaping ProgressSink
    ) async -> CallTool.Result {
        var strategy = strategy

        let providers = ProviderFactory.buildPanel(
            resolveKey: resolveKey,
            weights: strategy.providerWeights,
            models: strategy.providerModels,
            ollama: strategy.ollama,
            openAICompatible: strategy.openAICompatible
        )
        guard !providers.isEmpty else {
            return errorResult("""
                No LLM providers configured. Add keys via the Joint Chiefs setup app \
                or export OPENAI_API_KEY / GEMINI_API_KEY / GROK_API_KEY / ANTHROPIC_API_KEY.
                """)
        }
        if let requestedRounds {
            strategy.maxRounds = max(0, min(requestedRounds, 10))
        } else {
            strategy.maxRounds = max(0, min(strategy.maxRounds, 10))
        }

        let moderator = ProviderFactory.build(for: strategy.moderator, resolveKey: resolveKey, models: strategy.providerModels)
        let tiebreaker = ProviderFactory.buildTiebreaker(for: strategy.tiebreaker, resolveKey: resolveKey, models: strategy.providerModels)

        let orchestrator: DebateOrchestrator
        do {
            orchestrator = try DebateOrchestrator(
                providers: providers,
                moderator: moderator,
                tiebreaker: tiebreaker,
                strategy: strategy
            )
        } catch {
            return errorResult("Invalid strategy configuration: \(error.localizedDescription)")
        }

        let reviewContext = ReviewContext(
            code: code,
            filePath: filePath,
            goal: goal,
            context: extraContext
        )

        // Progress total = one slot for initial parallel reviews + one per
        // debate round + one for final consensus synthesis. Progress ticks
        // up monotonically as each stage boundary fires.
        let totalSteps = Double(strategy.maxRounds + 2)

        await progress(0, totalSteps, "Joint Chiefs: dispatching review to \(providers.count) provider\(providers.count == 1 ? "" : "s")")

        let stream = await orchestrator.runReviewStreaming(context: reviewContext)
        var finalSummary: ConsensusSummary?
        var fatalError: String?

        for await event in stream {
            switch event {
            case .initialReviewsComplete(let count):
                await progress(1, totalSteps, "Joint Chiefs: \(count) initial review\(count == 1 ? "" : "s") collected — starting debate")

            case .debateRoundStarting(let round, let totalRounds):
                await progress(Double(round), totalSteps, "Joint Chiefs: round \(round)/\(totalRounds) — providers responding")

            case .moderatorSynthesizing(let round):
                await progress(Double(round) + 0.5, totalSteps, "Joint Chiefs: moderator synthesizing round \(round)")

            case .debateConverged(let afterRound):
                await progress(Double(afterRound) + 0.9, totalSteps, "Joint Chiefs: positions converged after round \(afterRound)")

            case .buildingConsensus:
                await progress(totalSteps - 0.1, totalSteps, "Joint Chiefs: writing final consensus")

            case .providerFailed(let name, let error):
                // Non-fatal — the orchestrator continues with remaining providers.
                // Surface it so users know the panel degraded mid-run.
                await progress(-1, totalSteps, "Joint Chiefs: \(name) failed — continuing with remaining providers (\(error))")

            case .completed(let summary, _):
                finalSummary = summary
                await progress(totalSteps, totalSteps, "Joint Chiefs: review complete")

            case .failed(let error):
                fatalError = error

            case .sessionStarted, .providerReviewing, .providerReviewed,
                 .providerDebated, .moderatorSynthesized:
                // Per-provider chatter is too noisy for MCP progress (the spec
                // is for coarse milestones, not token-level streaming). Skip.
                break
            }
        }

        if let fatalError {
            return errorResult("Review failed: \(fatalError)")
        }

        guard let summary = finalSummary else {
            return errorResult("Review completed without producing a summary.")
        }

        return CallTool.Result(
            content: [.text(text: formatConsensus(summary), annotations: nil, _meta: nil)],
            isError: false
        )
    }

    // MARK: - Helpers

    private static func errorResult(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }

    /// MCP runs headless with no user-facing stderr channel; resolver errors
    /// (keychain locked, keygetter missing) must not crash the server. Log to
    /// stderr for operators, treat the provider as unconfigured.
    private static func resolveKey(_ provider: ProviderType) -> String? {
        do {
            return try APIKeyResolver.resolve(provider)
        } catch {
            let message = "Key resolution failed for \(provider.rawValue): \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return nil
        }
    }

    private static func formatConsensus(_ summary: ConsensusSummary) -> String {
        var lines: [String] = []
        lines.append("## Joint Chiefs Consensus")
        lines.append("Models: \(summary.modelsConsulted.joined(separator: ", ")) | Rounds: \(summary.roundsCompleted)")
        lines.append("")

        if summary.findings.isEmpty {
            lines.append("No issues found. The code looks good.")
        } else {
            for finding in summary.findings {
                lines.append("### \(finding.title) [\(finding.severity.rawValue.uppercased())] (\(finding.agreement.rawValue))")
                lines.append(finding.description)
                if !finding.recommendation.isEmpty {
                    lines.append("**Recommendation:** \(finding.recommendation)")
                }
                if !finding.location.isEmpty {
                    lines.append("**Location:** \(finding.location)")
                }
                if let raisedBy = finding.raisedBy, !raisedBy.isEmpty {
                    lines.append("**Raised by:** \(raisedBy.joined(separator: ", "))")
                }
                lines.append("")
            }
        }

        lines.append("---")
        lines.append(summary.recommendation)
        return lines.joined(separator: "\n")
    }
}
