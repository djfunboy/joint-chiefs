import ArgumentParser
import Foundation
import JointChiefsCore

struct Review: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Submit code for multi-model review"
    )

    @Argument(help: "File path to review")
    var file: String?

    @Flag(name: .long, help: "Read code from stdin")
    var stdin: Bool = false

    @Option(name: .long, help: "Your directive to the panel (e.g., \"focus on security\", \"how should we handle errors here?\")")
    var goal: String?

    @Option(name: .long, help: "Additional context for reviewers")
    var context: String?

    @Option(name: .long, help: "Number of debate rounds (overrides strategy)")
    var rounds: Int?

    @Option(name: .long, help: "Timeout per provider in seconds (overrides strategy)")
    var timeout: Int?

    @Option(name: .long, help: "Output format: summary, json, or full (default: summary)")
    var format: OutputFormat = .summary

    @Flag(name: .long, help: "Suppress streaming output, only show final result")
    var quiet: Bool = false

    mutating func validate() throws {
        guard file != nil || stdin else {
            throw ValidationError("Provide a file path or use --stdin to read from standard input")
        }
    }

    func run() async throws {
        let code = try readCode()
        let strategyForPanel = StrategyConfigStore.load()
        let providers = buildProviders(
            weights: strategyForPanel.providerWeights,
            models: strategyForPanel.providerModels,
            ollama: strategyForPanel.ollama,
            openAICompatible: strategyForPanel.openAICompatible
        )

        guard !providers.isEmpty else {
            stderr("No API keys found. Configure at least one provider:")
            stderr("  • Run the Joint Chiefs app to add a key via the Keychain, or")
            stderr("  • Export one of: OPENAI_API_KEY, GEMINI_API_KEY, GROK_API_KEY, ANTHROPIC_API_KEY")
            stderr("  • Or set OLLAMA_ENABLED=1 for local Ollama models")
            throw ExitCode.failure
        }

        var strategy = strategyForPanel
        if let rounds { strategy.maxRounds = rounds }
        if let timeout { strategy.timeoutSeconds = timeout }

        let moderator = ProviderFactory.build(for: strategy.moderator, resolveKey: self.resolveKey, models: strategy.providerModels)
        let tiebreaker = ProviderFactory.buildTiebreaker(for: strategy.tiebreaker, resolveKey: self.resolveKey, models: strategy.providerModels)

        let orchestrator = try DebateOrchestrator(
            providers: providers,
            moderator: moderator,
            tiebreaker: tiebreaker,
            strategy: strategy
        )

        let reviewContext = ReviewContext(
            code: code,
            filePath: file,
            goal: goal,
            context: context
        )

        if quiet {
            do {
                let (summary, _) = try await orchestrator.runReview(context: reviewContext)
                printOutput(summary: summary, format: format)
            } catch let error as OrchestratorError {
                stderr("Review failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            var finalSummary: ConsensusSummary?
            for await event in await orchestrator.runReviewStreaming(context: reviewContext) {
                switch event {
                case .completed(let summary, _):
                    finalSummary = summary
                case .failed(let error):
                    stderr("Review failed: \(error)")
                    throw ExitCode.failure
                default:
                    printEvent(event)
                }
            }
            if let summary = finalSummary {
                stderr("")
                stderr(divider("CONSENSUS"))
                stderr("")
                printOutput(summary: summary, format: format)
            }
        }
    }

    // MARK: - Event Display

    private func printEvent(_ event: ReviewEvent) {
        switch event {
        case .sessionStarted(let providers, let debateRounds):
            stderr(divider("JOINT CHIEFS CONVENED"))
            stderr("")
            stderr("  Generals present:")
            for name in providers {
                stderr("    \(Glyph.star) \(name)")
            }
            stderr("  Debate rounds: \(debateRounds)")
            stderr("")

        case .providerReviewing(let name):
            stderr("  \(Glyph.pending) \(name) reviewing...")

        case .providerReviewed(let review):
            stderr("  \(Glyph.check) \(review.providerName) (\(review.model)) reporting in")
            if review.findings.isEmpty {
                stderr("    No issues found.")
            } else {
                for finding in review.findings {
                    stderr("    \(severityIcon(finding.severity)) \(finding.title) [\(finding.severity.rawValue)]")
                }
            }
            stderr("")

        case .providerFailed(let name, let error):
            stderr("  \(Glyph.cross) \(name) — \(error)")
            stderr("")

        case .initialReviewsComplete(let count):
            stderr(divider("INITIAL REVIEWS COMPLETE (\(count) responded)"))
            stderr("")

        case .debateRoundStarting(let round, let total):
            stderr(divider("DEBATE ROUND \(round)/\(total)"))
            stderr("")

        case .providerDebated(let review, _):
            stderr("  \(Glyph.check) \(review.providerName) (\(review.model))")
            if review.findings.isEmpty {
                stderr("    No changes to position.")
            } else {
                for finding in review.findings {
                    stderr("    \(severityIcon(finding.severity)) \(finding.title) [\(finding.severity.rawValue)]")
                }
            }
            stderr("")

        case .moderatorSynthesizing(let round):
            stderr("  \(Glyph.pending) Claude synthesizing round \(round) brief...")

        case .moderatorSynthesized(let count, _):
            stderr("  \(Glyph.check) Consolidated to \(count) findings")
            stderr("")

        case .debateConverged(let afterRound):
            stderr("  \(Glyph.check) Positions converged after round \(afterRound) — stopping debate early")
            stderr("")

        case .buildingConsensus:
            stderr(divider("BUILDING CONSENSUS"))
            stderr("")

        case .completed, .failed:
            break
        }
    }

    // MARK: - Output Formatting

    private func printOutput(summary: ConsensusSummary, format: OutputFormat) {
        switch format {
        case .summary:
            printSummary(summary)
        case .json:
            printJSON(summary)
        case .full:
            printFull(summary)
        }
    }

    private func printSummary(_ summary: ConsensusSummary) {
        let models = summary.modelsConsulted.joined(separator: ", ")
        print("## Joint Chiefs Consensus")
        print("Models: \(models) | Rounds: \(summary.roundsCompleted)")
        print("")

        if summary.findings.isEmpty {
            print("No issues found. The code looks good.")
            return
        }

        for finding in summary.findings {
            let icon = severityIcon(finding.severity)
            let agreement = agreementLabel(finding.agreement)
            print("\(icon) **\(finding.title)** [\(finding.severity.rawValue.uppercased())] (\(agreement))")
            print("  \(finding.description)")
            if !finding.recommendation.isEmpty {
                print("  Recommendation: \(finding.recommendation)")
            }
            if !finding.location.isEmpty {
                print("  Location: \(finding.location)")
            }
            if let raisedBy = finding.raisedBy, !raisedBy.isEmpty {
                print("  Raised by: \(raisedBy.joined(separator: ", "))")
            }
            print("")
        }

        print("---")
        print(summary.recommendation)
    }

    private func printJSON(_ summary: ConsensusSummary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(summary),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    private func printFull(_ summary: ConsensusSummary) {
        printSummary(summary)
        print("")
        print("Transcript ID: \(summary.transcriptId)")
    }

    // MARK: - Code Reading

    private func readCode() throws -> String {
        if stdin {
            var lines: [String] = []
            while let line = readLine(strippingNewline: false) {
                lines.append(line)
            }
            let code = lines.joined()
            guard !code.isEmpty else {
                throw ValidationError("No input received from stdin")
            }
            return code
        }

        guard let filePath = file else {
            throw ValidationError("No file path provided")
        }

        let url = URL(fileURLWithPath: filePath)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ValidationError("Cannot read file '\(filePath)': \(error.localizedDescription)")
        }
    }

    // MARK: - Provider Setup

    private func buildProviders(
        weights: [ProviderType: Double],
        models: [ProviderType: String],
        ollama: OllamaConfig,
        openAICompatible: OpenAICompatibleConfig
    ) -> [any ReviewProvider] {
        ProviderFactory.buildPanel(
            resolveKey: self.resolveKey,
            weights: weights,
            models: models,
            ollama: ollama,
            openAICompatible: openAICompatible
        )
    }

    /// Env var → keygetter → nil. Surfaces keygetter errors to the user; silent
    /// "not configured" when neither source supplies a key.
    private func resolveKey(_ provider: ProviderType) -> String? {
        do {
            return try APIKeyResolver.resolve(provider)
        } catch {
            stderr("Key resolution failed for \(provider.rawValue): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Formatting Helpers

    private enum Glyph {
        static let star = "\u{2605}"      // ★
        static let check = "\u{2713}"     // ✓
        static let cross = "\u{2717}"     // ✗
        static let pending = "\u{25CB}"   // ○
    }

    private func severityIcon(_ severity: Severity) -> String {
        switch severity {
        case .critical: "\u{1F534}" // 🔴
        case .high: "\u{1F7E0}"     // 🟠
        case .medium: "\u{1F7E1}"   // 🟡
        case .low: "\u{1F535}"      // 🔵
        }
    }

    private func agreementLabel(_ level: AgreementLevel) -> String {
        switch level {
        case .unanimous: "unanimous"
        case .majority: "majority"
        case .split: "split"
        case .solo: "solo"
        }
    }

    private func divider(_ title: String) -> String {
        let pad = max(0, 60 - title.count - 4)
        let left = String(repeating: "─", count: 2)
        let right = String(repeating: "─", count: pad)
        return "\(left) \(title) \(right)"
    }

    private func stderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum OutputFormat: String, ExpressibleByArgument, Sendable {
    case summary
    case json
    case full
}
