import Foundation

public enum OrchestratorError: Error, Sendable, LocalizedError {
    case noProviders
    case allProvidersFailed(errors: [String])
    case reviewCancelled
    case invalidConfiguration(reason: String)

    public var errorDescription: String? {
        switch self {
        case .noProviders:
            "No review providers configured. Add at least one provider in Settings."
        case .allProvidersFailed(let errors):
            "All providers failed during review:\n" + errors.joined(separator: "\n")
        case .reviewCancelled:
            "The review was cancelled before completion."
        case .invalidConfiguration(let reason):
            "Invalid orchestrator configuration: \(reason)"
        }
    }
}
