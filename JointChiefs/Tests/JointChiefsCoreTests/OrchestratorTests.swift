import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Debate Orchestrator Tests")
struct OrchestratorTests {

    private let sampleContext = ReviewContext(
        code: "func login() { }",
        filePath: "auth.swift",
        goal: "security review"
    )

    // MARK: - Happy Path

    @Test("Full review cycle with 2 providers and 2 debate rounds")
    func fullReviewCycle() async throws {
        let finding1 = Finding(
            title: "SQL Injection",
            description: "User input not sanitized",
            severity: .critical,
            agreement: .solo,
            recommendation: "Use parameterized queries",
            location: "line 10"
        )
        let finding2 = Finding(
            title: "Missing auth check",
            description: "No authorization verification",
            severity: .high,
            agreement: .solo,
            recommendation: "Add auth middleware",
            location: "line 5"
        )

        let provider1 = MockProvider(name: "ModelA", model: "a-v1", reviewFindings: [finding1])
        let provider2 = MockProvider(name: "ModelB", model: "b-v1", reviewFindings: [finding2])

        let orchestrator = DebateOrchestrator(providers: [provider1, provider2], debateRounds: 2)
        let (summary, transcript) = try await orchestrator.runReview(context: sampleContext)

        // 3 rounds: 1 initial + 2 debate
        #expect(transcript.rounds.count == 3)
        #expect(transcript.rounds[0].phase == .independent)
        #expect(transcript.rounds[1].phase == .debate)
        #expect(transcript.rounds[2].phase == .debate)
        #expect(transcript.status == .completed)
        #expect(transcript.consensusSummary != nil)

        #expect(summary.modelsConsulted.count == 2)
        #expect(summary.roundsCompleted == 3)
        #expect(!summary.findings.isEmpty)
        #expect(summary.transcriptId == transcript.id)
    }

    // MARK: - No Providers

    @Test("Throws noProviders when no providers configured")
    func noProviders() async {
        let orchestrator = DebateOrchestrator(providers: [])

        await #expect(throws: OrchestratorError.self) {
            try await orchestrator.runReview(context: sampleContext)
        }
    }

    // MARK: - All Providers Fail

    @Test("Throws allProvidersFailed when every provider errors")
    func allProvidersFail() async {
        let failing1 = MockProvider(name: "Fail1", shouldFail: true)
        let failing2 = MockProvider(name: "Fail2", shouldFail: true)

        let orchestrator = DebateOrchestrator(providers: [failing1, failing2])

        await #expect(throws: OrchestratorError.self) {
            try await orchestrator.runReview(context: sampleContext)
        }
    }

    // MARK: - Graceful Degradation

    @Test("Continues when one provider fails during initial review")
    func gracefulDegradation() async throws {
        let finding = Finding(
            title: "Test issue",
            description: "Found something",
            severity: .medium,
            agreement: .solo,
            recommendation: "Fix it",
            location: "line 1"
        )
        let working = MockProvider(name: "Working", reviewFindings: [finding])
        let failing = MockProvider(name: "Failing", shouldFail: true)

        let orchestrator = DebateOrchestrator(providers: [working, failing], debateRounds: 1)
        let (summary, transcript) = try await orchestrator.runReview(context: sampleContext)

        // Should complete with only the working provider
        #expect(transcript.status == .completed)
        #expect(transcript.rounds[0].responses.count == 1)
        #expect(summary.modelsConsulted.count == 2) // Both were consulted, even if one failed
    }

    // MARK: - Zero Debate Rounds

    @Test("Zero debate rounds skips debate phase")
    func zeroDebateRounds() async throws {
        let finding = Finding(
            title: "Minor issue",
            description: "Small thing",
            severity: .low,
            agreement: .solo,
            recommendation: "Maybe fix",
            location: "line 1"
        )
        let provider = MockProvider(name: "Solo", reviewFindings: [finding])

        let orchestrator = DebateOrchestrator(providers: [provider], debateRounds: 0)
        let (_, transcript) = try await orchestrator.runReview(context: sampleContext)

        // Only the initial round, no debate rounds
        // Note: debateRounds: 0 means 1...0 range which is empty
        #expect(transcript.rounds.count == 1)
        #expect(transcript.rounds[0].phase == .independent)
    }

    // MARK: - Transcript Structure

    @Test("Transcript captures file path and goal from context")
    func transcriptMetadata() async throws {
        let provider = MockProvider(name: "Test")
        let orchestrator = DebateOrchestrator(providers: [provider], debateRounds: 0)
        let (_, transcript) = try await orchestrator.runReview(context: sampleContext)

        #expect(transcript.filePath == "auth.swift")
        #expect(transcript.goal == "security review")
        #expect(transcript.codeSnippet == "func login() { }")
    }
}
