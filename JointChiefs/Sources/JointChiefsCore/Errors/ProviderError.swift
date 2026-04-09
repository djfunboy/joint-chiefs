import Foundation

public enum ProviderError: Error, Sendable, LocalizedError {
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case serverError(statusCode: Int, message: String)
    case malformedResponse(detail: String)
    case networkError(underlying: String)
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "Authentication failed. Please verify your API key is valid."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Rate limited by provider. Retry after \(Int(retryAfter)) seconds."
            } else {
                "Rate limited by provider. Please wait before retrying."
            }
        case .timeout:
            "Request timed out. The provider may be experiencing high load."
        case .serverError(let statusCode, let message):
            "Server error (\(statusCode)): \(message)"
        case .malformedResponse(let detail):
            "Received an unexpected response from the provider: \(detail)"
        case .networkError(let underlying):
            "Network error: \(underlying)"
        case .missingAPIKey:
            "No API key configured for this provider. Add one in Settings."
        }
    }
}
