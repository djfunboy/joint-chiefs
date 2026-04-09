import Foundation

public struct ProviderReview: Codable, Sendable {
    public var providerName: String
    public var model: String
    public var content: String
    public var findings: [Finding]

    public init(providerName: String, model: String, content: String, findings: [Finding]) {
        self.providerName = providerName
        self.model = model
        self.content = content
        self.findings = findings
    }
}
