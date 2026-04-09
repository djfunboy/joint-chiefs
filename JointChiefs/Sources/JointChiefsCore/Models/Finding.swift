import Foundation

public struct Finding: Codable, Hashable, Sendable {
    public var title: String
    public var description: String
    public var severity: Severity
    public var agreement: AgreementLevel
    public var recommendation: String
    public var location: String

    public init(title: String, description: String, severity: Severity, agreement: AgreementLevel, recommendation: String, location: String) {
        self.title = title
        self.description = description
        self.severity = severity
        self.agreement = agreement
        self.recommendation = recommendation
        self.location = location
    }
}
