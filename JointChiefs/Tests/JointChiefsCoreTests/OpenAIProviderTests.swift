import Testing
import Foundation
@testable import JointChiefsCore

@Suite("OpenAI Provider Tests", .serialized)
struct OpenAIProviderTests {

    private let testEndpoint = URL(string: "https://api.openai.com/v1")!

    private func makeProvider(session: URLSession? = nil) -> OpenAIProvider {
        OpenAIProvider(
            apiKey: "test-key-123",
            model: "gpt-5.4",
            endpoint: testEndpoint,
            urlSession: session ?? TestHelpers.makeTestURLSession()
        )
    }

    // MARK: - Successful Review

    @Test("Successful review returns parsed findings")
    func successfulReview() async throws {
        let responseContent = TestHelpers.makeSuccessResponseJSON()
        let responseData = TestHelpers.makeChatCompletionResponse(content: responseContent)

        MockURLProtocol.requestHandler = { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.providerName == "OpenAI")
        #expect(review.model == "gpt-5.4")
        #expect(review.findings.count == 2)
        #expect(review.findings[0].title == "Missing error handling")
        #expect(review.findings[0].severity == .high)
        #expect(review.findings[1].title == "Unused variable")
        #expect(review.findings[1].severity == .low)
    }

    // MARK: - Authentication Error

    @Test("401 response throws authenticationFailed")
    func authenticationError() async {
        MockURLProtocol.requestHandler = { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 401)
            return (response, Data("Unauthorized".utf8))
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()

        await #expect(throws: ProviderError.self) {
            try await provider.review(code: context.code, context: context)
        }
    }

    // MARK: - Rate Limit Error

    @Test("429 response throws rateLimited with retry-after")
    func rateLimitError() async {
        MockURLProtocol.requestHandler = { request in
            let response = TestHelpers.makeHTTPResponse(
                url: request.url!,
                statusCode: 429,
                headers: ["Retry-After": "30"]
            )
            return (response, Data("Rate limited".utf8))
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()

        do {
            _ = try await provider.review(code: context.code, context: context)
            Issue.record("Expected rateLimited error")
        } catch let error as ProviderError {
            if case .rateLimited(let retryAfter) = error {
                #expect(retryAfter == 30)
            } else {
                Issue.record("Expected rateLimited, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Server Error

    @Test("500 response throws serverError")
    func serverError() async {
        MockURLProtocol.requestHandler = { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 500)
            return (response, Data("Internal Server Error".utf8))
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()

        await #expect(throws: ProviderError.self) {
            try await provider.review(code: context.code, context: context)
        }
    }

    // MARK: - Malformed Response

    @Test("Non-JSON content falls back to single finding")
    func malformedResponseFallback() async throws {
        let responseData = TestHelpers.makeChatCompletionResponse(content: "This is just plain text, not JSON.")

        MockURLProtocol.requestHandler = { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.findings.count == 1)
        #expect(review.findings[0].title == "Review Response")
        #expect(review.findings[0].severity == .medium)
    }

    // MARK: - Debate

    @Test("Debate request includes prior findings in prompt")
    func debateIncludesPriorFindings() async throws {
        MockURLProtocol.lastRequestBody = nil
        let responseContent = TestHelpers.makeSuccessResponseJSON()
        let responseData = TestHelpers.makeChatCompletionResponse(content: responseContent)

        MockURLProtocol.requestHandler = { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let priorFindings = [TestHelpers.makeSampleFinding()]
        _ = try await provider.debate(code: "let x = 1", priorFindings: priorFindings, round: 1)

        let body = try #require(MockURLProtocol.lastRequestBody)
        let bodyString = String(data: body, encoding: .utf8) ?? ""

        #expect(bodyString.contains("Missing error handling"))
        #expect(bodyString.contains("round 1"))
    }

    // MARK: - Test Connection

    @Test("testConnection returns true on success")
    func testConnectionSuccess() async throws {
        let responseData = TestHelpers.makeChatCompletionResponse(content: "ok")

        MockURLProtocol.requestHandler = { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let result = try await provider.testConnection()
        #expect(result == true)
    }

    // MARK: - Request Structure

    @Test("Review request has correct headers and endpoint")
    func requestStructure() async throws {
        var capturedRequest: URLRequest?
        let responseContent = TestHelpers.makeSuccessResponseJSON()
        let responseData = TestHelpers.makeChatCompletionResponse(content: responseContent)

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        _ = try await provider.review(code: context.code, context: context)

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.hasSuffix("/chat/completions") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
