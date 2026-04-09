import Foundation

// MARK: - ConsensusBuilder

/// Synthesizes findings from the final debate round into a consensus summary.
///
/// After multiple debate rounds, models have had the chance to argue, concede, and converge.
/// The consensus is built from the **final round** — where positions have settled — rather
/// than merging all rounds equally.
public enum ConsensusBuilder {

    /// Synthesizes a consensus summary from the debate transcript.
    ///
    /// Uses findings from the final round only. Earlier rounds served as debate context
    /// and are preserved in the transcript but don't pollute the consensus.
    ///
    /// - Parameters:
    ///   - transcript: The complete debate transcript containing all rounds.
    ///   - providers: The providers that participated in the review.
    /// - Returns: A `ConsensusSummary` with deduplicated, ranked findings.
    public static func synthesize(
        transcript: DebateTranscript,
        providers: [any ReviewProvider]
    ) -> ConsensusSummary {
        let providerCount = providers.count

        // Use only the final round's findings — that's where positions converged
        let finalFindings: [Finding]
        if let lastRound = transcript.rounds.last {
            finalFindings = lastRound.responses.flatMap { $0.findings }
        } else {
            finalFindings = []
        }

        let respondedCount = transcript.rounds.last?.responses.count ?? providerCount
        let grouped = groupBySimilarity(finalFindings)
        let mergedFindings = mergeGroups(grouped, respondedCount: respondedCount)
        let sorted = sortFindings(mergedFindings)

        let recommendation = buildRecommendation(from: sorted)
        let modelsConsulted = providers.map { "\($0.name) (\($0.model))" }

        return ConsensusSummary(
            findings: sorted,
            recommendation: recommendation,
            modelsConsulted: modelsConsulted,
            roundsCompleted: transcript.rounds.count,
            transcriptId: transcript.id
        )
    }

    // MARK: - Model-Based Synthesis

    /// Uses a deciding model (e.g., Claude) to read the full debate and produce the consensus.
    ///
    /// The deciding model sees all rounds and is asked to deduplicate, resolve disagreements,
    /// and produce a final ranked list of findings.
    public static func synthesizeWithModel(
        transcript: DebateTranscript,
        providers: [any ReviewProvider],
        decidingModel: any ReviewProvider,
        timeoutSeconds: Int
    ) async throws -> ConsensusSummary {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // Build an ANONYMOUS summary of the debate for the deciding model.
        // Provider names are replaced with "Reviewer A", "Reviewer B", etc.
        // so the judge evaluates arguments on merit, not provider reputation.
        var debateSummary = "## Code Review Debate Transcript\n\n"
        debateSummary += "**File:** \(transcript.filePath)\n"
        debateSummary += "**Goal:** \(transcript.goal)\n\n"

        // Build a stable mapping of provider names to anonymous labels
        var providerLabels: [String: String] = [:]
        let labels = ["A", "B", "C", "D", "E", "F", "G", "H"]
        var labelIndex = 0
        for round in transcript.rounds {
            for response in round.responses {
                let key = "\(response.providerName) (\(response.model))"
                if providerLabels[key] == nil, labelIndex < labels.count {
                    providerLabels[key] = "Reviewer \(labels[labelIndex])"
                    labelIndex += 1
                }
            }
        }

        for round in transcript.rounds {
            let phaseLabel = round.phase == .independent ? "Independent Review" : "Debate Round \(round.roundNumber)"
            debateSummary += "### \(phaseLabel)\n\n"
            for response in round.responses {
                let key = "\(response.providerName) (\(response.model))"
                let label = providerLabels[key] ?? "Reviewer"
                debateSummary += "**\(label):**\n"
                if response.findings.isEmpty {
                    debateSummary += "No findings.\n\n"
                } else {
                    for finding in response.findings {
                        debateSummary += "- [\(finding.severity.rawValue.uppercased())] \(finding.title): \(finding.description)\n"
                    }
                    debateSummary += "\n"
                }
            }
        }

        let context = ReviewContext(
            code: debateSummary,
            filePath: transcript.filePath,
            goal: "Synthesize the consensus from this multi-model code review debate. You are the deciding judge. Read all rounds, resolve disagreements, deduplicate similar findings, and produce the final ranked list. If models disagreed on severity, use your judgment. If a model made a case for downgrading a finding and the argument is sound, respect it. Only include findings that survived the debate.",
            context: "You are the consensus builder for a panel of AI code reviewers. Return your final findings as JSON."
        )

        let review = try await decidingModel.review(code: context.code, context: context)

        let modelsConsulted = providers.map { "\($0.name) (\($0.model))" }

        return ConsensusSummary(
            findings: review.findings,
            recommendation: review.content,
            modelsConsulted: modelsConsulted,
            roundsCompleted: transcript.rounds.count,
            transcriptId: transcript.id
        )
    }

    // MARK: - Between-Round Synthesis

    /// Asks the moderator (Claude) to consolidate a round's findings into a concise brief.
    ///
    /// Used between debate rounds so each general receives Claude's synthesis
    /// rather than raw findings from all other generals. This keeps prompt size constant.
    public static func synthesizeRound(
        findings: [Finding],
        code: String,
        goal: String,
        moderator: any ReviewProvider
    ) async throws -> [Finding] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let findingsData = try encoder.encode(findings)
        let findingsJSON = String(data: findingsData, encoding: .utf8) ?? "[]"

        let context = ReviewContext(
            code: findingsJSON,
            filePath: nil,
            goal: """
                You are moderating a code review debate. Multiple reviewers have submitted findings. \
                Deduplicate similar findings, resolve conflicting severities by picking the most justified level, \
                and produce a clean consolidated list. Keep it concise — max 15 findings. \
                Drop trivial or redundant items. Preserve the strongest version of each unique finding. \
                The original review goal was: \(goal)
                """,
            context: nil
        )

        let review = try await moderator.review(code: context.code, context: context)
        return review.findings
    }

    // MARK: - Grouping

    /// Groups findings by semantic similarity using keyword overlap on normalized titles.
    private static func groupBySimilarity(_ findings: [Finding]) -> [[Finding]] {
        var groups: [[Finding]] = []

        for finding in findings {
            let normalized = normalizeTitle(finding.title)
            var matched = false

            for i in groups.indices {
                let groupNormalized = normalizeTitle(groups[i][0].title)
                if titlesAreSimilar(normalized, groupNormalized) {
                    groups[i].append(finding)
                    matched = true
                    break
                }
            }

            if !matched {
                groups.append([finding])
            }
        }

        return groups
    }

    /// Normalizes a title for comparison: lowercase, strip prefixes, remove punctuation.
    private static func normalizeTitle(_ title: String) -> String {
        var t = title.lowercased()

        // Strip common prefixes models add
        let prefixes = ["disagreement:", "agreement:", "revised:", "new:"]
        for prefix in prefixes {
            if t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count))
            }
        }

        // Remove punctuation and extra whitespace
        t = t.replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        t = t.split(separator: " ").joined(separator: " ")
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Determines if two normalized titles refer to the same finding using keyword overlap.
    private static func titlesAreSimilar(_ a: String, _ b: String) -> Bool {
        let wordsA = Set(a.split(separator: " ").map(String.init))
        let wordsB = Set(b.split(separator: " ").map(String.init))

        // Filter out very short/common words
        let stopWords: Set<String> = ["in", "of", "the", "a", "an", "and", "or", "for", "is", "to", "with", "via", "by", "on", "no", "not", "from", "may", "be"]
        let sigA = wordsA.subtracting(stopWords)
        let sigB = wordsB.subtracting(stopWords)

        guard !sigA.isEmpty, !sigB.isEmpty else { return false }

        let overlap = sigA.intersection(sigB)
        let smaller = min(sigA.count, sigB.count)

        // If more than half the significant words overlap, it's the same finding
        return Double(overlap.count) / Double(smaller) >= 0.5
    }

    // MARK: - Merging

    /// Merges each group of related findings into a single finding with consensus metadata.
    private static func mergeGroups(
        _ groups: [[Finding]],
        respondedCount: Int
    ) -> [Finding] {
        groups.map { findings in
            let raisedByCount = findings.count
            let agreement = determineAgreement(
                raisedBy: raisedByCount,
                totalProviders: respondedCount
            )

            // Use the highest severity any provider assigned
            let highestSeverity = findings.map(\.severity).max() ?? .low

            // Use the title from the highest-severity finding
            let bestFinding = findings.max(by: { $0.severity < $1.severity }) ?? findings[0]
            let title = bestFinding.title

            // Use the best description (from the highest-severity finding)
            let description = bestFinding.description
            let recommendation = bestFinding.recommendation
            let location = bestFinding.location

            return Finding(
                title: title,
                description: description,
                severity: highestSeverity,
                agreement: agreement,
                recommendation: recommendation,
                location: location
            )
        }
    }

    private static func determineAgreement(
        raisedBy count: Int,
        totalProviders: Int
    ) -> AgreementLevel {
        guard totalProviders > 0 else { return .solo }

        if count >= totalProviders, totalProviders > 1 {
            return .unanimous
        } else if count > totalProviders / 2 {
            return .majority
        } else if count > 1 {
            return .split
        } else {
            return .solo
        }
    }

    // MARK: - Sorting

    /// Sorts findings by severity (critical first), then by agreement level.
    private static func sortFindings(_ findings: [Finding]) -> [Finding] {
        findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return agreementRank(lhs.agreement) > agreementRank(rhs.agreement)
        }
    }

    private static func agreementRank(_ level: AgreementLevel) -> Int {
        switch level {
        case .unanimous: 4
        case .majority: 3
        case .split: 2
        case .solo: 1
        }
    }

    // MARK: - Recommendation

    private static func buildRecommendation(from findings: [Finding]) -> String {
        guard !findings.isEmpty else {
            return "No findings raised by any provider. The code looks good."
        }

        let criticalCount = findings.filter { $0.severity == .critical }.count
        let highCount = findings.filter { $0.severity == .high }.count

        var parts: [String] = []

        if criticalCount > 0 {
            parts.append("\(criticalCount) critical issue\(criticalCount == 1 ? "" : "s") found")
        }
        if highCount > 0 {
            parts.append("\(highCount) high-severity issue\(highCount == 1 ? "" : "s") found")
        }

        let topFindings = Array(findings.prefix(3))
        let topSummaries = topFindings.map { "\u{2022} \($0.title): \($0.recommendation)" }

        if parts.isEmpty {
            return "Minor issues found. Top recommendations:\n" + topSummaries.joined(separator: "\n")
        }

        return parts.joined(separator: ", ") + ". Top recommendations:\n" + topSummaries.joined(separator: "\n")
    }
}
