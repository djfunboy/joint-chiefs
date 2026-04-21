import Foundation
@testable import JointChiefsCore

/// A mock ReviewProvider for testing the orchestrator and consensus builder.
struct MockProvider: ReviewProvider, Sendable {
    let name: String
    let model: String
    let providerType: ProviderType
    let reviewFindings: [Finding]
    let debateFindings: [Finding]
    let shouldFail: Bool

    init(
        name: String = "MockModel",
        model: String = "mock-v1",
        providerType: ProviderType = .openAI,
        reviewFindings: [Finding] = [],
        debateFindings: [Finding]? = nil,
        shouldFail: Bool = false
    ) {
        self.name = name
        self.model = model
        self.providerType = providerType
        self.reviewFindings = reviewFindings
        self.debateFindings = debateFindings ?? reviewFindings
        self.shouldFail = shouldFail
    }

    func review(code: String, context: ReviewContext) async throws -> ProviderReview {
        if shouldFail { throw ProviderError.timeout }
        return ProviderReview(
            providerName: name,
            model: model,
            content: "Mock review",
            findings: reviewFindings
        )
    }

    func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview {
        if shouldFail { throw ProviderError.timeout }
        return ProviderReview(
            providerName: name,
            model: model,
            content: "Mock debate round \(round)",
            findings: debateFindings
        )
    }

    func testConnection() async throws -> Bool {
        if shouldFail { throw ProviderError.timeout }
        return true
    }
}
