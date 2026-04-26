import Foundation

/// Calls the OpenAI chat completions API to perform code reviews and participate in debate rounds.
public struct OpenAIProvider: ReviewProvider {

    // MARK: - Properties

    public let name: String
    public let model: String
    public let providerType: ProviderType = .openAI
    private let endpoint: URL
    private let apiKey: String
    private let urlSession: URLSession

    // MARK: - Init

    /// Creates an OpenAI provider.
    ///
    /// - Parameters:
    ///   - apiKey: The OpenAI API key used for authentication.
    ///   - model: The model identifier to use. Defaults to `"gpt-5.5"`.
    ///   - endpoint: The base URL for the OpenAI API. Defaults to `https://api.openai.com/v1`.
    ///   - urlSession: The URL session to use for requests. Defaults to `.shared`.
    public init(
        apiKey: String,
        model: String = "gpt-5.5",
        endpoint: URL = URL(string: "https://api.openai.com/v1")!,
        urlSession: URLSession = .shared
    ) {
        self.name = "OpenAI"
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

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userMessage),
        ]

        let (content, findings) = try await sendRequest(messages: messages, responseFormat: .json)
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

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userMessage),
        ]

        let (content, findings) = try await sendRequest(messages: messages, responseFormat: .json)
        return ProviderReview(providerName: name, model: model, content: content, findings: findings)
    }

    public func testConnection() async throws -> Bool {
        let messages = [
            ChatMessage(role: "user", content: "Respond with the word ok."),
        ]

        let _ = try await sendRequest(messages: messages, responseFormat: nil)
        return true
    }

    // MARK: - Private Methods

    /// Sends a chat completion request to the OpenAI API.
    ///
    /// - Parameters:
    ///   - messages: The chat messages to send.
    ///   - responseFormat: Optional response format (e.g., JSON mode).
    /// - Returns: A tuple of the raw content string and parsed findings.
    /// - Throws: `ProviderError` for authentication, rate limiting, server errors, or network issues.
    private func sendRequest(
        messages: [ChatMessage],
        responseFormat: ResponseFormat?
    ) async throws -> (String, [Finding]) {
        let requestURL = endpoint.appendingPathComponent("chat/completions")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: 0.2,
            responseFormat: responseFormat,
            stream: true
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

        // For error status codes, collect the full body for the error message
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
            default:
                throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        }

        // Stream SSE response and collect content tokens
        var content = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let chunkData = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: chunkData),
                  let token = chunk.choices.first?.delta.content else {
                continue
            }
            content += token
        }

        guard !content.isEmpty else {
            throw ProviderError.malformedResponse(detail: "Stream produced no content")
        }

        let findings = parseFindings(from: content)
        return (content, findings)
    }

    /// Attempts to parse structured findings from a JSON response string.
    ///
    /// Falls back to a single finding with the raw content if JSON parsing fails.
    ///
    /// - Parameter content: The raw response content string.
    /// - Returns: An array of parsed `Finding` objects.
    private func parseFindings(from content: String) -> [Finding] {
        guard let data = content.data(using: .utf8) else {
            return [makeFallbackFinding(from: content)]
        }

        do {
            let response = try JSONDecoder().decode(FindingsResponse.self, from: data)
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

// MARK: - Private DTO

private struct FindingsResponse: Decodable {
    let findings: [FindingDTO]
}

private struct FindingDTO: Decodable {
    let title: String
    let description: String
    let severity: String
    let recommendation: String
    let location: String
}
