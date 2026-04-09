import Foundation

public enum ReviewStatus: String, Codable, Sendable {
    case inProgress, completed, failed
}
