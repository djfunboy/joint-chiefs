import Foundation

public enum Severity: String, Codable, CaseIterable, Comparable, Sendable {
    case critical, high, medium, low

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        let order: [Severity] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}
