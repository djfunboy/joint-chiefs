import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Review Prompts Tests")
struct ReviewPromptsTests {

    // MARK: - reviewSystem

    @Test("Review prompt carries the calibration anchor and still demands JSON")
    func reviewSystemCalibration() {
        let p = ReviewPrompts.reviewSystem
        // Calibration must be present — this is the whole point of the prompt.
        #expect(p.contains("gold-plate"))
        #expect(p.contains("not a finding"))
        #expect(p.contains("do not inflate"))
        // The output contract must survive any calibration edit.
        #expect(p.contains("Return ONLY valid JSON"))
        #expect(p.contains("\"findings\""))
    }

    // MARK: - debateSystem

    @Test("Debate prompt interpolates the round and renders prior findings")
    func debateSystemInterpolation() {
        let finding = Finding(
            title: "Unhandled nil in parser",
            description: "Force-unwrap can crash on malformed input.",
            severity: .high,
            agreement: .solo,
            recommendation: "Use guard let.",
            location: "parse()"
        )
        let p = ReviewPrompts.debateSystem(round: 3, priorFindings: [finding])

        #expect(p.contains("debate round 3"))
        #expect(p.contains("Unhandled nil in parser"))
        #expect(p.contains("[HIGH]"))
        // Converge-and-cut framing — the anti-ratchet.
        #expect(p.contains("converge and cut"))
        #expect(p.contains("DROPPED is a first-class"))
        #expect(p.contains("Return ONLY valid JSON"))
    }

    @Test("Debate prompt renders an empty prior-findings list without crashing")
    func debateSystemEmptyFindings() {
        let p = ReviewPrompts.debateSystem(round: 1, priorFindings: [])
        #expect(p.contains("debate round 1"))
        #expect(p.contains("Prior findings:"))
    }

    // MARK: - Moderator prompts

    @Test("Between-round synthesis carries the 10-finding cap and cut instruction")
    func betweenRoundSynthesisCalibration() {
        let p = ReviewPrompts.betweenRoundSynthesisGoal(goal: "security audit")
        #expect(p.contains("Hard limit: 10"))
        #expect(p.contains("CUT any finding"))
        #expect(p.contains("over-engineering"))
        // The caller's goal must still be threaded through.
        #expect(p.contains("security audit"))
    }

    @Test("Final consensus prompt carries the pragmatic-editor framing")
    func finalConsensusCalibration() {
        #expect(ReviewPrompts.finalConsensusGoal.contains("pragmatic"))
        #expect(ReviewPrompts.finalConsensusGoal.contains("Cut speculative"))
        #expect(ReviewPrompts.finalConsensusContext.contains("consensus builder"))
    }
}
