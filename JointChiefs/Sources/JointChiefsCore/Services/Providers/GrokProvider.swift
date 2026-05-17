import Foundation

/// Calls the xAI Grok API (OpenAI-compatible) to perform code reviews and participate in debate rounds.
public struct GrokProvider: ReviewProvider {

    // MARK: - Properties

    public let name: String
    public let model: String
    public let providerType: ProviderType = .grok
    private let endpoint: URL
    private let apiKey: String
    private let urlSession: URLSession

    // MARK: - Init

    /// Creates a Grok provider.
    ///
    /// - Parameters:
    ///   - apiKey: The xAI API key used for authentication.
    ///   - model: The model identifier to use. Defaults to `"grok-4.3"`.
    ///   - endpoint: The base URL for the xAI API. Defaults to `https://api.x.ai/v1`.
    ///   - urlSession: The URL session to use for requests. Defaults to `.shared`.
    public init(
        apiKey: String,
        model: String = "grok-4.3",
        endpoint: URL = URL(string: "https://api.x.ai/v1")!,
        urlSession: URLSession = .shared
    ) {
        self.name = "Grok"
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    // MARK: - ReviewProvider

    public func review(code: String, context: ReviewContext) async throws -> ProviderReview {
        let systemPrompt = ReviewPrompts.reviewSystem

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
        let systemPrompt = ReviewPrompts.debateSystem(round: round, priorFindings: priorFindings)

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

    /// Sends a chat completion request to the xAI API.
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
            let response = try JSONDecoder().decode(GrokFindingsResponse.self, from: data)
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

private struct GrokFindingsResponse: Decodable {
    let findings: [GrokFindingDTO]
}

private struct GrokFindingDTO: Decodable {
    let title: String
    let description: String
    let severity: String
    let recommendation: String
    let location: String
}
