import Foundation

public struct Finding: Codable, Hashable, Sendable {
    public var title: String
    public var description: String
    public var severity: Severity
    public var agreement: AgreementLevel
    public var recommendation: String
    public var location: String
    /// Providers that raised this finding. Populated during consensus building
    /// for display in the final output. Nil during debate rounds (anonymous).
    public var raisedBy: [String]?

    public init(title: String, description: String, severity: Severity, agreement: AgreementLevel, recommendation: String, location: String, raisedBy: [String]? = nil) {
        self.title = title
        self.description = description
        self.severity = severity
        self.agreement = agreement
        self.recommendation = recommendation
        self.location = location
        self.raisedBy = raisedBy
    }
}
