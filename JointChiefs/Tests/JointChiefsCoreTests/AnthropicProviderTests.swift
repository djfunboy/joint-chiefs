import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Anthropic Provider Tests", .serialized)
struct AnthropicProviderTests {

    private let testEndpoint = URL(string: "https://api.anthropic.com")!

    private func makeProvider(session: URLSession? = nil) -> AnthropicProvider {
        AnthropicProvider(
            apiKey: "test-key-123",
            model: "claude-opus-4-6",
            endpoint: testEndpoint,
            urlSession: session ?? TestHelpers.makeTestURLSession()
        )
    }

    // MARK: - Successful Review

    @Test("Plain JSON response parses to structured findings")
    func plainJSONParses() async throws {
        let responseData = TestHelpers.makeAnthropicStreamingResponse(
            content: TestHelpers.makeSuccessResponseJSON()
        )

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.providerName == "Anthropic")
        #expect(review.findings.count == 2)
        #expect(review.findings[0].title == "Missing error handling")
        #expect(review.findings[0].severity == .high)
    }

    // MARK: - Regression: Code-Fenced JSON

    @Test("JSON wrapped in ```json code fences parses correctly")
    func fencedJSONParses() async throws {
        let fenced = "```json\n\(TestHelpers.makeSuccessResponseJSON())\n```"
        let responseData = TestHelpers.makeAnthropicStreamingResponse(content: fenced)

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.findings.count == 2)
        #expect(review.findings[0].title == "Missing error handling")
        #expect(review.findings[1].title == "Unused variable")
    }

    @Test("JSON wrapped in plain ``` fences parses correctly")
    func plainFencedJSONParses() async throws {
        let fenced = "```\n\(TestHelpers.makeSuccessResponseJSON())\n```"
        let responseData = TestHelpers.makeAnthropicStreamingResponse(content: fenced)

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.findings.count == 2)
    }

    @Test("JSON with conversational preamble parses correctly")
    func preambledJSONParses() async throws {
        let preambled = "Here is the review:\n\n\(TestHelpers.makeSuccessResponseJSON())"
        let responseData = TestHelpers.makeAnthropicStreamingResponse(content: preambled)

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.findings.count == 2)
        #expect(review.findings[0].title == "Missing error handling")
    }

    @Test("JSON followed by trailing prose with stray braces still parses")
    func trailingProseBracesParses() async throws {
        // Synthesis responses commonly add explanatory prose after the JSON object
        // that contains stray brackets (`{fallback}`, `}` in sentences). The extractor
        // must find the first balanced `{...}` span — not greedily grab everything
        // between the first `{` and the last `}`, which is what used to happen and
        // produced malformed JSON that fell back to a single "Review Response"
        // finding with the entire raw content stuffed into `description`.
        let trailing = """
        \(TestHelpers.makeSuccessResponseJSON())

        Note: the handler at `{fallback}` was reviewed but not flagged.
        """
        let responseData = TestHelpers.makeAnthropicStreamingResponse(content: trailing)

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.findings.count == 2)
        #expect(review.findings[0].title == "Missing error handling")
        // No finding should carry the raw content (prose + JSON + prose) in its description.
        for finding in review.findings {
            #expect(!finding.description.contains("```"))
            #expect(!finding.description.contains("\"findings\""))
        }
    }

    @Test("Preamble containing braces does not derail parsing")
    func preambleWithBracesParses() async throws {
        // Claude sometimes opens with a code-sample preamble: "In Swift, `{...}` means...".
        // The greedy first-to-last strategy grabbed the `{` from the preamble and the
        // `}` from the trailing JSON, producing invalid JSON. The balanced extractor
        // must skip over non-JSON brace pairs and locate the real findings object.
        let preambled = """
        Quick note: Swift closures use `{ ... }` syntax, which can be confusing.
        Here is the review:

        \(TestHelpers.makeSuccessResponseJSON())
        """
        let responseData = TestHelpers.makeAnthropicStreamingResponse(content: preambled)

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.findings.count == 2)
        for finding in review.findings {
            #expect(!finding.description.contains("Swift closures"))
        }
    }

    // MARK: - Fallback

    @Test("Response with no JSON object falls back to single finding")
    func nonJSONFallsBack() async throws {
        let responseData = TestHelpers.makeAnthropicStreamingResponse(
            content: "This is just plain text, not JSON."
        )

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        let review = try await provider.review(code: context.code, context: context)

        #expect(review.findings.count == 1)
        #expect(review.findings[0].title == "Review Response")
    }

    // MARK: - Errors

    @Test("401 response throws authenticationFailed")
    func authenticationError() async {
        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 401)
            return (response, Data("Unauthorized".utf8))
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()

        await #expect(throws: ProviderError.self) {
            try await provider.review(code: context.code, context: context)
        }
    }

    // MARK: - Request Structure

    @Test("Review request uses Anthropic headers and endpoint")
    func requestStructure() async throws {
        var capturedRequest: URLRequest?
        let responseData = TestHelpers.makeAnthropicStreamingResponse(
            content: TestHelpers.makeSuccessResponseJSON()
        )

        MockURLProtocol.setHandler(forHost: "api.anthropic.com") { request in
            capturedRequest = request
            let response = TestHelpers.makeHTTPResponse(url: request.url!, statusCode: 200)
            return (response, responseData)
        }

        let provider = makeProvider()
        let context = TestHelpers.makeSampleReviewContext()
        _ = try await provider.review(code: context.code, context: context)

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.hasSuffix("/v1/messages") == true)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key-123")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }
}
