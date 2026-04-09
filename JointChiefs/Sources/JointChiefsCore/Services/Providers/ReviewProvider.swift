import Foundation

/// A provider that can review code using an LLM and participate in multi-model debate rounds.
public protocol ReviewProvider: Sendable {
    /// The display name of the provider (e.g., "OpenAI", "Gemini").
    var name: String { get }

    /// The specific model identifier used by this provider (e.g., "gpt-5.4", "gemini-3.1-pro-preview").
    var model: String { get }

    /// Performs an initial code review.
    ///
    /// - Parameters:
    ///   - code: The source code to review.
    ///   - context: Additional context guiding the review (goal, language, focus areas).
    /// - Returns: The provider's review containing findings and an overall assessment.
    /// - Throws: `ProviderError` if the review fails.
    func review(code: String, context: ReviewContext) async throws -> ProviderReview

    /// Participates in a debate round by reviewing prior findings from other providers.
    ///
    /// - Parameters:
    ///   - code: The original source code under review.
    ///   - priorFindings: Findings from previous review or debate rounds.
    ///   - round: The current debate round number (1-based).
    /// - Returns: The provider's updated review after considering prior findings.
    /// - Throws: `ProviderError` if the debate round fails.
    func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview

    /// Tests connectivity and authentication with the provider's API.
    ///
    /// - Returns: `true` if the connection is successful and the API key is valid.
    /// - Throws: `ProviderError` if the connection test fails.
    func testConnection() async throws -> Bool
}
