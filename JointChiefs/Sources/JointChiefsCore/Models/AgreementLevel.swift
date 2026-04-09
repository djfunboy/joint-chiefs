import Foundation

public enum AgreementLevel: String, Codable, Sendable {
    case unanimous, majority, split, solo
}
