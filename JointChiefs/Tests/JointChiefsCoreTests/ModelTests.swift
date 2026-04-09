import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Model Type Tests")
struct ModelTests {

    // MARK: - Severity

    @Test("Severity ordering: low < medium < high < critical")
    func severityComparable() {
        #expect(Severity.low < .medium)
        #expect(Severity.medium < .high)
        #expect(Severity.high < .critical)
        #expect(!(Severity.critical < .low))
    }

    @Test("Severity round-trips through JSON")
    func severityCodable() throws {
        for severity in Severity.allCases {
            let data = try JSONEncoder().encode(severity)
            let decoded = try JSONDecoder().decode(Severity.self, from: data)
            #expect(decoded == severity)
        }
    }

    // MARK: - Finding

    @Test("Finding round-trips through JSON")
    func findingCodable() throws {
        let finding = TestHelpers.makeSampleFinding()
        let data = try JSONEncoder().encode(finding)
        let decoded = try JSONDecoder().decode(Finding.self, from: data)
        #expect(decoded == finding)
    }

    // MARK: - ProviderType

    @Test("ProviderType has correct default endpoints")
    func providerTypeDefaultEndpoints() {
        #expect(ProviderType.openAI.defaultEndpoint == "https://api.openai.com/v1")
        #expect(ProviderType.gemini.defaultEndpoint == "https://generativelanguage.googleapis.com/v1beta")
        #expect(ProviderType.grok.defaultEndpoint == "https://api.x.ai/v1")
        #expect(ProviderType.ollama.defaultEndpoint == "http://localhost:11434")
    }

    @Test("ProviderType has correct default models")
    func providerTypeDefaultModels() {
        #expect(ProviderType.openAI.defaultModel == "gpt-5.4")
        #expect(ProviderType.gemini.defaultModel == "gemini-3.1-pro-preview")
        #expect(ProviderType.grok.defaultModel == "grok-3")
        #expect(ProviderType.ollama.defaultModel == "llama3")
    }

    // MARK: - ReviewContext

    @Test("ReviewContext round-trips with all fields")
    func reviewContextCodableFull() throws {
        let context = ReviewContext(code: "let x = 1", filePath: "test.swift", goal: "review", context: "extra")
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(ReviewContext.self, from: data)
        #expect(decoded.code == context.code)
        #expect(decoded.filePath == context.filePath)
        #expect(decoded.goal == context.goal)
        #expect(decoded.context == context.context)
    }

    @Test("ReviewContext round-trips with nil optionals")
    func reviewContextCodableMinimal() throws {
        let context = ReviewContext(code: "let x = 1")
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(ReviewContext.self, from: data)
        #expect(decoded.code == context.code)
        #expect(decoded.filePath == nil)
        #expect(decoded.goal == nil)
        #expect(decoded.context == nil)
    }

    // MARK: - ProviderReview

    @Test("ProviderReview round-trips through JSON")
    func providerReviewCodable() throws {
        let review = ProviderReview(
            providerName: "OpenAI",
            model: "gpt-5.4",
            content: "Looks good",
            findings: [TestHelpers.makeSampleFinding()]
        )
        let data = try JSONEncoder().encode(review)
        let decoded = try JSONDecoder().decode(ProviderReview.self, from: data)
        #expect(decoded.providerName == review.providerName)
        #expect(decoded.model == review.model)
        #expect(decoded.content == review.content)
        #expect(decoded.findings == review.findings)
    }

    // MARK: - AgreementLevel

    @Test("AgreementLevel round-trips through JSON")
    func agreementLevelCodable() throws {
        let cases: [AgreementLevel] = [.unanimous, .majority, .split, .solo]
        for level in cases {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(AgreementLevel.self, from: data)
            #expect(decoded == level)
        }
    }
}
