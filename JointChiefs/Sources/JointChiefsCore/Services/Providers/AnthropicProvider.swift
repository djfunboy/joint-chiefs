import Foundation

/// Calls the Anthropic Messages API to perform code reviews and participate in debate rounds.
public struct AnthropicProvider: ReviewProvider {

    // MARK: - Properties

    public let name: String
    public let model: String
    private let endpoint: URL
    private let apiKey: String
    private let urlSession: URLSession

    // MARK: - Init

    /// Creates an Anthropic provider.
    ///
    /// - Parameters:
    ///   - apiKey: The Anthropic API key used for authentication.
    ///   - model: The model identifier to use. Defaults to `"claude-opus-4-6"`.
    ///   - endpoint: The base URL for the Anthropic API. Defaults to `https://api.anthropic.com`.
    ///   - urlSession: The URL session to use for requests. Defaults to `.shared`.
    public init(
        apiKey: String,
        model: String = "claude-opus-4-6",
        endpoint: URL = URL(string: "https://api.anthropic.com")!,
        urlSession: URLSession = .shared
    ) {
        self.name = "Anthropic"
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    // MARK: - ReviewProvider

    public func review(code: String, context: ReviewContext) async throws -> ProviderReview {
        let systemPrompt = """
            You are a senior code reviewer. Analyze the provided code and return a JSON object with:
            - "summary": a brief overall assessment of the code quality
            - "findings": an array of issues found, where each finding has:
              - "title": short description of the issue
              - "description": detailed explanation
              - "severity": one of "critical", "high", "medium", "low"
              - "recommendation": how to fix the issue
              - "location": where in the code the issue occurs (function name, line range, or section)

            Return ONLY valid JSON. No markdown, no code fences.
            """

        var userMessage = "Review the following code:\n\n```\n\(code)\n```"
        if let goal = context.goal {
            userMessage += "\n\nReview goal: \(goal)"
        }
        if let additionalContext = context.context {
            userMessage += "\n\nAdditional context: \(additionalContext)"
        }

        let (content, findings) = try await sendRequest(systemPrompt: systemPrompt, userMessage: userMessage)
        return ProviderReview(providerName: name, model: model, content: content, findings: findings)
    }

    public func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview {
        let findingsText = priorFindings.map { finding in
            "- [\(finding.severity.rawValue.uppercased())] \(finding.title): \(finding.description) (Location: \(finding.location))"
        }.joined(separator: "\n")

        let systemPrompt = """
            You are a senior code reviewer in debate round \(round). Other reviewers have produced the findings below.

            Prior findings:
            \(findingsText)

            You MUST directly address each prior finding by title. For each one:
            - AGREE and state why if you believe it is correct and properly rated
            - CHALLENGE and explain your reasoning if you believe it is wrong, overstated, or misrated in severity
            - REVISE with your corrected version if it is partially correct

            Then, if you have NEW findings not yet raised, add them.

            Do NOT simply restate prior findings. Take a clear position on each one. If you previously raised \
            a finding that others challenged, either defend your position with specific reasoning or concede.

            Return a JSON object with:
            - "summary": your assessment after considering all prior findings and challenges
            - "findings": your complete final list of findings after this round of debate
              Each finding has: "title", "description", "severity" (critical/high/medium/low), \
            "recommendation", "location"

            Return ONLY valid JSON. No markdown, no code fences.
            """

        let userMessage = "Code under review:\n\n```\n\(code)\n```\n\nRespond with your positions on each finding above."

        let (content, findings) = try await sendRequest(systemPrompt: systemPrompt, userMessage: userMessage)
        return ProviderReview(providerName: name, model: model, content: content, findings: findings)
    }

    public func testConnection() async throws -> Bool {
        let _ = try await sendRequest(systemPrompt: nil, userMessage: "Respond with the word ok.")
        return true
    }

    // MARK: - Private Methods

    /// Sends a message request to the Anthropic Messages API.
    ///
    /// - Parameters:
    ///   - systemPrompt: Optional system prompt to guide the model's behavior.
    ///   - userMessage: The user message to send.
    /// - Returns: A tuple of the raw content string and parsed findings.
    /// - Throws: `ProviderError` for authentication, rate limiting, server errors, or network issues.
    private func sendRequest(
        systemPrompt: String?,
        userMessage: String
    ) async throws -> (String, [Finding]) {
        let requestURL = endpoint.appendingPathComponent("v1/messages")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = AnthropicRequest(
            model: model,
            maxTokens: 4096,
            stream: true,
            system: systemPrompt,
            messages: [AnthropicMessage(role: "user", content: userMessage)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await urlSession.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw ProviderError.timeout
        } catch let urlError as URLError {
            throw ProviderError.networkError(underlying: urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse(detail: "Response was not an HTTP response")
        }

        // For error status codes, read the full body to build a meaningful error message
        if httpResponse.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            switch httpResponse.statusCode {
            case 401:
                throw ProviderError.authenticationFailed
            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(TimeInterval.init)
                throw ProviderError.rateLimited(retryAfter: retryAfter)
            case 500...599:
                throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
            default:
                throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        }

        // Stream SSE response and collect content from text deltas
        var content = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            guard let eventData = data.data(using: .utf8),
                  let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: eventData),
                  event.type == "content_block_delta",
                  let text = event.delta?.text else {
                continue
            }
            content += text
        }

        guard !content.isEmpty else {
            throw ProviderError.malformedResponse(detail: "Stream produced no content")
        }
        let findings = parseFindings(from: content)
        return (content, findings)
    }

    /// Attempts to parse structured findings from a response string.
    ///
    /// Claude has no enforced JSON-output mode (unlike OpenAI's `response_format`), so
    /// despite the prompt instruction to return only JSON, responses regularly arrive
    /// wrapped in ```json ... ``` code fences or with surrounding prose. This method
    /// extracts the first balanced `{...}` span before decoding, falling back to a
    /// single finding with the raw content if no JSON object is found.
    ///
    /// - Parameter content: The raw response content string.
    /// - Returns: An array of parsed `Finding` objects.
    private func parseFindings(from content: String) -> [Finding] {
        guard let json = extractJSONObject(from: content),
              let data = json.data(using: .utf8) else {
            return [makeFallbackFinding(from: content)]
        }

        do {
            let response = try JSONDecoder().decode(AnthropicFindingsResponse.self, from: data)
            return response.findings.map { dto in
                Finding(
                    title: dto.title,
                    description: dto.description,
                    severity: Severity(rawValue: dto.severity) ?? .medium,
                    agreement: .solo,
                    recommendation: dto.recommendation,
                    location: dto.location
                )
            }
        } catch {
            return [makeFallbackFinding(from: content)]
        }
    }

    /// Returns the substring spanning the first `{` to the last `}` in `content`,
    /// or `nil` if none exists. JSONDecoder validates structural correctness — this
    /// is just a cheap way to strip code fences and conversational preamble.
    private func extractJSONObject(from content: String) -> String? {
        guard let firstBrace = content.firstIndex(of: "{"),
              let lastBrace = content.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return nil
        }
        return String(content[firstBrace...lastBrace])
    }

    private func makeFallbackFinding(from content: String) -> Finding {
        Finding(
            title: "Review Response",
            description: content,
            severity: .medium,
            agreement: .solo,
            recommendation: "",
            location: ""
        )
    }
}

// MARK: - Private Anthropic API Types

private struct AnthropicMessage: Codable, Sendable {
    let role: String
    let content: String
}

private struct AnthropicRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let system: String?
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case stream
        case system
        case messages
    }
}

private struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: AnthropicDelta?
}

private struct AnthropicDelta: Decodable {
    let type: String?
    let text: String?
}

private struct AnthropicResponse: Decodable, Sendable {
    let id: String
    let content: [ContentBlock]
    let role: String
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case id, content, role
        case stopReason = "stop_reason"
    }
}

private struct ContentBlock: Decodable, Sendable {
    let type: String
    let text: String
}

private struct AnthropicFindingsResponse: Decodable {
    let findings: [AnthropicFindingDTO]
}

private struct AnthropicFindingDTO: Decodable {
    let title: String
    let description: String
    let severity: String
    let recommendation: String
    let location: String
}
