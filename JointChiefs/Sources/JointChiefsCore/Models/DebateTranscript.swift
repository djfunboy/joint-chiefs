import Foundation

public struct DebateTranscript: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var filePath: String
    public var goal: String
    public var codeSnippet: String
    public var rounds: [TranscriptRound]
    public var consensusSummary: ConsensusSummary?
    public var status: ReviewStatus

    public init(filePath: String, goal: String, codeSnippet: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.filePath = filePath
        self.goal = goal
        self.codeSnippet = codeSnippet
        self.rounds = []
        self.consensusSummary = nil
        self.status = .inProgress
    }
}

public struct TranscriptRound: Codable, Sendable {
    public var roundNumber: Int
    public var phase: ReviewPhase
    public var responses: [ProviderReview]

    public init(roundNumber: Int, phase: ReviewPhase, responses: [ProviderReview]) {
        self.roundNumber = roundNumber
        self.phase = phase
        self.responses = responses
    }
}
