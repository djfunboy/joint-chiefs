import Foundation
import JointChiefsCore
import MCP

/// The single tool exposed by the Joint Chiefs MCP server. Runs a multi-model debate
/// review against supplied code and returns a consensus summary as structured text.
enum JointChiefsReviewTool {
    static let name = "joint_chiefs_review"

    static let definition = Tool(
        name: name,
        description: """
            Submit code to a panel of AI models (OpenAI, Gemini, Grok, Claude) for a \
            structured multi-round debate review. Each model reviews independently, \
            then challenges the others' findings across up to 5 rounds with adaptive \
            early termination on convergence. Claude moderates and writes the final \
            consensus. Returns categorized findings with severity, agreement level, \
            and a unified recommendation. Grounded in the Multi-Agent Debate research \
            (Liang et al., 2023).
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

    static func invoke(arguments: [String: Value]) async -> CallTool.Result {
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
        let providers = ProviderFactory.buildPanel(resolveKey: resolveKey)
        guard !providers.isEmpty else {
            return errorResult("""
                No LLM providers configured. Add keys via the Joint Chiefs setup app \
                or export OPENAI_API_KEY / GEMINI_API_KEY / GROK_API_KEY / ANTHROPIC_API_KEY.
                """)
        }

        // MCP clamps rounds to [0, 10] to keep autonomous agents from driving
        // absurdly long debates per request; beyond that, per-connection rate
        // limits (task #26) are the right control surface.
        var strategy = StrategyConfigStore.load()
        if let requestedRounds {
            strategy.maxRounds = max(0, min(requestedRounds, 10))
        } else {
            strategy.maxRounds = max(0, min(strategy.maxRounds, 10))
        }

        let moderator = ProviderFactory.build(for: strategy.moderator, resolveKey: resolveKey)
        let tiebreaker = ProviderFactory.buildTiebreaker(for: strategy.tiebreaker, resolveKey: resolveKey)

        let orchestrator = DebateOrchestrator(
            providers: providers,
            moderator: moderator,
            tiebreaker: tiebreaker,
            strategy: strategy
        )

        let reviewContext = ReviewContext(
            code: code,
            filePath: filePath,
            goal: goal,
            context: extraContext
        )

        do {
            let (summary, _) = try await orchestrator.runReview(context: reviewContext)
            return CallTool.Result(
                content: [.text(text: formatConsensus(summary), annotations: nil, _meta: nil)],
                isError: false
            )
        } catch {
            return errorResult("Review failed: \(error.localizedDescription)")
        }
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
