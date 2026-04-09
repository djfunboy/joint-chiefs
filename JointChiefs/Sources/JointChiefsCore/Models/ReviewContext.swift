import Foundation

public struct ReviewContext: Codable, Sendable {
    public var code: String
    public var filePath: String?
    public var goal: String?
    public var context: String?

    public init(code: String, filePath: String? = nil, goal: String? = nil, context: String? = nil) {
        self.code = code
        self.filePath = filePath
        self.goal = goal
        self.context = context
    }
}
