import Testing
import Foundation
@testable import JointChiefsCore

/// Regression coverage for the moderator/tiebreaker pre-flight gap: the setup app
/// let any provider be picked as moderator regardless of whether a key was saved
/// for it, so Save accepted a strategy that blew up at review time.
@Suite("Role Key Preflight Tests")
struct RoleKeyPreflightTests {

    private func config(
        moderator: ModeratorSelection,
        tiebreaker: TiebreakerSelection = .sameAsModerator
    ) -> StrategyConfig {
        var config = StrategyConfig.default
        config.moderator = moderator
        config.tiebreaker = tiebreaker
        return config
    }

    // MARK: - Moderator

    @Test("Moderator with no saved key is reported")
    func moderatorWithoutKeyIsReported() {
        let issues = config(moderator: .claude).roleKeyIssues(configuredProviders: [])
        #expect(issues.count == 1)
        #expect(issues.first?.role == .moderator)
        #expect(issues.first?.selection == .claude)
        #expect(issues.first?.providerType == .anthropic)
    }

    @Test("Moderator with a saved key is clean")
    func moderatorWithKeyIsClean() {
        let issues = config(moderator: .claude).roleKeyIssues(configuredProviders: [.anthropic])
        #expect(issues.isEmpty)
    }

    @Test("Every LLM moderator maps to the provider whose key it needs")
    func everyModeratorMapsToItsProvider() {
        let expected: [ModeratorSelection: ProviderType] = [
            .claude: .anthropic,
            .openai: .openAI,
            .gemini: .gemini,
            .grok: .grok
        ]
        for (selection, provider) in expected {
            let issues = config(moderator: selection).roleKeyIssues(configuredProviders: [])
            #expect(issues.first?.providerType == provider)
            // The same config is clean once that one provider's key is present.
            #expect(config(moderator: selection).roleKeyIssues(configuredProviders: [provider]).isEmpty)
        }
    }

    @Test("Code-based moderator needs no key")
    func codeModeratorNeedsNoKey() {
        #expect(config(moderator: ModeratorSelection.none).roleKeyIssues(configuredProviders: []).isEmpty)
    }

    // MARK: - Tiebreaker

    @Test("Specific tiebreaker with no saved key is reported")
    func specificTiebreakerWithoutKeyIsReported() {
        let issues = config(moderator: .claude, tiebreaker: .specific(.grok))
            .roleKeyIssues(configuredProviders: [.anthropic])
        #expect(issues.count == 1)
        #expect(issues.first?.role == .tiebreaker)
        #expect(issues.first?.providerType == .grok)
    }

    @Test("Tiebreaker set to same-as-moderator raises no separate issue")
    func sameAsModeratorTiebreakerIsNotDoubleReported() {
        let issues = config(moderator: .claude, tiebreaker: .sameAsModerator)
            .roleKeyIssues(configuredProviders: [])
        #expect(issues.count == 1)
        #expect(issues.first?.role == .moderator)
    }

    @Test("Both roles unkeyed reports moderator first, then tiebreaker")
    func bothRolesReportedInOrder() {
        let issues = config(moderator: .claude, tiebreaker: .specific(.openai))
            .roleKeyIssues(configuredProviders: [])
        #expect(issues.count == 2)
        #expect(issues[0].role == .moderator)
        #expect(issues[1].role == .tiebreaker)
    }

    @Test("Code-based tiebreaker needs no key")
    func codeTiebreakerNeedsNoKey() {
        let issues = config(moderator: .claude, tiebreaker: .specific(ModeratorSelection.none))
            .roleKeyIssues(configuredProviders: [.anthropic])
        #expect(issues.isEmpty)
    }

    // MARK: - Message

    @Test("Issue message names the role and the provider to fix")
    func messageNamesRoleAndProvider() throws {
        let issue = try #require(config(moderator: .grok).roleKeyIssues(configuredProviders: []).first)
        #expect(issue.message.contains("Moderator"))
        #expect(issue.message.contains("Grok"))
    }

    @Test("Summary stays short enough for a single-line pill; guidance carries the fix")
    func summaryIsShortAndGuidanceIsActionable() throws {
        for selection in ModeratorSelection.allCases where selection != ModeratorSelection.none {
            let issue = try #require(
                config(moderator: selection).roleKeyIssues(configuredProviders: []).first
            )
            // The pill that renders `summary` is lineLimit(1) — a long string
            // truncates and hides the point. Guidance wraps separately.
            #expect(issue.summary.count <= 48)
            #expect(issue.summary.contains(selection.displayName))
            #expect(issue.guidance.contains("API Keys"))
            #expect(issue.message.contains(issue.summary))
            #expect(issue.message.contains(issue.guidance))
        }
    }
}
