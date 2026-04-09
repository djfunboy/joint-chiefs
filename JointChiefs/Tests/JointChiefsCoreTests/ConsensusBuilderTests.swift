import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Consensus Builder Tests")
struct ConsensusBuilderTests {

    // MARK: - Agreement Levels

    @Test("Unanimous agreement when all providers raise same finding")
    func unanimousAgreement() {
        let finding = Finding(
            title: "Race condition",
            description: "Concurrent access",
            severity: .critical,
            agreement: .solo,
            recommendation: "Add actor",
            location: "line 10"
        )

        let providers: [any ReviewProvider] = [
            MockProvider(name: "A", model: "a"),
            MockProvider(name: "B", model: "b"),
        ]

        // Both providers raise the same finding in the initial round
        let transcript = makeTranscript(rounds: [
            TranscriptRound(roundNumber: 0, phase: .independent, responses: [
                ProviderReview(providerName: "A", model: "a", content: "", findings: [finding]),
                ProviderReview(providerName: "B", model: "b", content: "", findings: [finding]),
            ])
        ])

        let summary = ConsensusBuilder.synthesize(transcript: transcript, providers: providers)

        let raceFinding = summary.findings.first { $0.title == "Race condition" }
        #expect(raceFinding != nil)
        #expect(raceFinding?.agreement == .unanimous)
        #expect(raceFinding?.severity == .critical)
    }

    // MARK: - Solo Finding

    @Test("Solo agreement when only one provider raises a finding")
    func soloAgreement() {
        let finding = Finding(
            title: "Style issue",
            description: "Naming convention",
            severity: .low,
            agreement: .solo,
            recommendation: "Rename",
            location: "line 1"
        )

        let providers: [any ReviewProvider] = [
            MockProvider(name: "A"),
            MockProvider(name: "B"),
        ]

        let transcript = makeTranscript(rounds: [
            TranscriptRound(roundNumber: 0, phase: .independent, responses: [
                ProviderReview(providerName: "A", model: "a", content: "", findings: [finding]),
                ProviderReview(providerName: "B", model: "b", content: "", findings: []),
            ])
        ])

        let summary = ConsensusBuilder.synthesize(transcript: transcript, providers: providers)

        let styleFinding = summary.findings.first { $0.title == "Style issue" }
        #expect(styleFinding != nil)
        #expect(styleFinding?.agreement == .solo)
    }

    // MARK: - Severity Ranking

    @Test("Findings sorted by severity with critical first")
    func severityRanking() {
        let low = Finding(title: "Unused variable", description: "", severity: .low, agreement: .solo, recommendation: "", location: "")
        let critical = Finding(title: "SQL injection vulnerability", description: "", severity: .critical, agreement: .solo, recommendation: "", location: "")
        let medium = Finding(title: "Missing error handling", description: "", severity: .medium, agreement: .solo, recommendation: "", location: "")

        let providers: [any ReviewProvider] = [MockProvider(name: "A")]

        let transcript = makeTranscript(rounds: [
            TranscriptRound(roundNumber: 0, phase: .independent, responses: [
                ProviderReview(providerName: "A", model: "a", content: "", findings: [low, critical, medium]),
            ])
        ])

        let summary = ConsensusBuilder.synthesize(transcript: transcript, providers: providers)

        #expect(summary.findings.count == 3)
        #expect(summary.findings[0].severity == .critical)
        #expect(summary.findings[1].severity == .medium)
        #expect(summary.findings[2].severity == .low)
    }

    // MARK: - Uses Highest Severity

    @Test("Takes highest severity when providers disagree on severity")
    func highestSeverityWins() {
        let findingLow = Finding(title: "Auth bug", description: "Missing check", severity: .medium, agreement: .solo, recommendation: "Fix", location: "line 5")
        let findingHigh = Finding(title: "Auth bug", description: "Critical gap", severity: .critical, agreement: .solo, recommendation: "Fix now", location: "line 5")

        let providers: [any ReviewProvider] = [
            MockProvider(name: "A"),
            MockProvider(name: "B"),
        ]

        let transcript = makeTranscript(rounds: [
            TranscriptRound(roundNumber: 0, phase: .independent, responses: [
                ProviderReview(providerName: "A", model: "a", content: "", findings: [findingLow]),
                ProviderReview(providerName: "B", model: "b", content: "", findings: [findingHigh]),
            ])
        ])

        let summary = ConsensusBuilder.synthesize(transcript: transcript, providers: providers)

        let authFinding = summary.findings.first { $0.title.lowercased().contains("auth") }
        #expect(authFinding?.severity == .critical)
    }

    // MARK: - Empty Findings

    @Test("No findings produces appropriate recommendation")
    func emptyFindings() {
        let providers: [any ReviewProvider] = [MockProvider(name: "A")]
        let transcript = makeTranscript(rounds: [
            TranscriptRound(roundNumber: 0, phase: .independent, responses: [
                ProviderReview(providerName: "A", model: "a", content: "", findings: []),
            ])
        ])

        let summary = ConsensusBuilder.synthesize(transcript: transcript, providers: providers)

        #expect(summary.findings.isEmpty)
        #expect(summary.recommendation.contains("looks good"))
    }

    // MARK: - Models Consulted

    @Test("Models consulted lists all providers")
    func modelsConsulted() {
        let providers: [any ReviewProvider] = [
            MockProvider(name: "OpenAI", model: "gpt-5.4"),
            MockProvider(name: "Gemini", model: "gemini-3.1-pro-preview"),
        ]

        let transcript = makeTranscript(rounds: [
            TranscriptRound(roundNumber: 0, phase: .independent, responses: [])
        ])

        let summary = ConsensusBuilder.synthesize(transcript: transcript, providers: providers)

        #expect(summary.modelsConsulted.count == 2)
        #expect(summary.modelsConsulted[0].contains("OpenAI"))
        #expect(summary.modelsConsulted[1].contains("Gemini"))
    }

    // MARK: - Helpers

    private func makeTranscript(rounds: [TranscriptRound]) -> DebateTranscript {
        var transcript = DebateTranscript(filePath: "test.swift", goal: "test", codeSnippet: "let x = 1")
        transcript.rounds = rounds
        return transcript
    }
}
