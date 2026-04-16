import Foundation
@testable import JointChiefsCore

enum TestHelpers {

    static func makeTestURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func makeSampleFinding() -> Finding {
        Finding(
            title: "Missing error handling",
            description: "The function does not handle the error case.",
            severity: .high,
            agreement: .solo,
            recommendation: "Add a do/catch block.",
            location: "authenticate() line 42"
        )
    }

    static func makeSampleReviewContext() -> ReviewContext {
        ReviewContext(
            code: "func hello() { print(\"hello\") }",
            filePath: "test.swift",
            goal: "general review"
        )
    }

    static func makeSuccessResponseJSON() -> String {
        """
        {
            "findings": [
                {
                    "title": "Missing error handling",
                    "description": "The function does not handle failures.",
                    "severity": "high",
                    "recommendation": "Add do/catch block.",
                    "location": "line 10"
                },
                {
                    "title": "Unused variable",
                    "description": "Variable 'tmp' is declared but never used.",
                    "severity": "low",
                    "recommendation": "Remove the unused variable.",
                    "location": "line 5"
                }
            ],
            "summary": "Code has some issues that should be addressed."
        }
        """
    }

    /// Builds SSE-formatted streaming response data from a content string.
    ///
    /// Splits the content into per-character chunks to simulate token-by-token streaming,
    /// then appends the `[DONE]` sentinel. Compatible with `urlSession.bytes(for:)` line iteration.
    static func makeChatCompletionResponse(content: String) -> Data {
        var sseLines: [String] = []
        for char in content {
            let chunk: [String: Any] = [
                "choices": [
                    ["delta": ["content": String(char)]]
                ]
            ]
            let json = try! JSONSerialization.data(withJSONObject: chunk)
            sseLines.append("data: \(String(data: json, encoding: .utf8)!)")
        }
        sseLines.append("data: [DONE]")
        let body = sseLines.joined(separator: "\n") + "\n"
        return Data(body.utf8)
    }

    /// Builds Anthropic-style SSE streaming response data from a content string.
    ///
    /// Emits one `content_block_delta` event per character to simulate token-by-token
    /// streaming through `URLSession.bytes(for:)` line iteration.
    static func makeAnthropicStreamingResponse(content: String) -> Data {
        var sseLines: [String] = []
        for char in content {
            let event: [String: Any] = [
                "type": "content_block_delta",
                "delta": ["type": "text_delta", "text": String(char)]
            ]
            let json = try! JSONSerialization.data(withJSONObject: event)
            sseLines.append("data: \(String(data: json, encoding: .utf8)!)")
        }
        let body = sseLines.joined(separator: "\n") + "\n"
        return Data(body.utf8)
    }

    static func makeHTTPResponse(url: URL, statusCode: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}
