import Foundation

public struct ConsensusSummary: Codable, Sendable {
    public var findings: [Finding]
    public var recommendation: String
    public var modelsConsulted: [String]
    public var roundsCompleted: Int
    public var transcriptId: UUID

    public init(
        findings: [Finding],
        recommendation: String,
        modelsConsulted: [String],
        roundsCompleted: Int,
        transcriptId: UUID
    ) {
        self.findings = findings
        self.recommendation = recommendation
        self.modelsConsulted = modelsConsulted
        self.roundsCompleted = roundsCompleted
        self.transcriptId = transcriptId
    }
}
