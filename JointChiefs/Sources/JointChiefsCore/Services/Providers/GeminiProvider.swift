import Foundation

/// Calls the Google Gemini streamGenerateContent SSE API to perform code reviews and participate in debate rounds.
public struct GeminiProvider: ReviewProvider {

    // MARK: - Properties

    public let name: String
    public let model: String
    public let providerType: ProviderType = .gemini
    private let endpoint: URL
    private let apiKey: String
    private let urlSession: URLSession

    // MARK: - Init

    /// Creates a Gemini provider.
    ///
    /// - Parameters:
    ///   - apiKey: The Google AI API key used for authentication (passed as query parameter).
    ///   - model: The model identifier to use. Defaults to `"gemini-3.1-pro-preview"`.
    ///   - endpoint: The base URL for the Gemini API. Defaults to `https://generativelanguage.googleapis.com/v1beta`.
    ///   - urlSession: The URL session to use for requests. Defaults to `.shared`.
    public init(
        apiKey: String,
        model: String = "gemini-3.1-pro-preview",
        endpoint: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        urlSession: URLSession = .shared
    ) {
        self.name = "Gemini"
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

        let (content, findings) = try await sendRequest(
            systemInstruction: systemPrompt,
            userMessage: userMessage
        )
        return ProviderReview(providerName: name, model: model, content: content, findings: findings)
    }

    public func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview {
        let systemPrompt = ReviewPrompts.debateSystem(round: round, priorFindings: priorFindings)

        let userMessage = "Code under review:\n\n```\n\(code)\n```\n\nRespond with your positions on each finding above."

        let (content, findings) = try await sendRequest(
            systemInstruction: systemPrompt,
            userMessage: userMessage
        )
        return ProviderReview(providerName: name, model: model, content: content, findings: findings)
    }

    public func testConnection() async throws -> Bool {
        let _ = try await sendRequest(
            systemInstruction: nil,
            userMessage: "Respond with the word ok."
        )
        return true
    }

    // MARK: - Private Methods

    /// Sends a streaming generateContent request to the Gemini API via SSE.
    ///
    /// Uses the `streamGenerateContent` endpoint with `alt=sse` to receive tokens incrementally.
    /// All text chunks are concatenated into a single response.
    ///
    /// - Parameters:
    ///   - systemInstruction: Optional system instruction for the model.
    ///   - userMessage: The user message to send.
    /// - Returns: A tuple of the raw content string and parsed findings.
    /// - Throws: `ProviderError` for authentication, rate limiting, server errors, or network issues.
    private func sendRequest(
        systemInstruction: String?,
        userMessage: String
    ) async throws -> (String, [Finding]) {
        let path = "models/\(model):streamGenerateContent"
        var requestURL = endpoint.appendingPathComponent(path)
        requestURL = requestURL.appending(queryItems: [
            URLQueryItem(name: "alt", value: "sse"),
            URLQueryItem(name: "key", value: apiKey),
        ])

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GeminiRequest(
            systemInstruction: systemInstruction.map { GeminiContent(parts: [GeminiPart(text: $0)]) },
            contents: [GeminiContent(parts: [GeminiPart(text: userMessage)])],
            generationConfig: GeminiGenerationConfig(responseMimeType: "application/json")
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

        // For error responses, collect the full body for error messaging
        if !(200..<300).contains(httpResponse.statusCode) {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            switch httpResponse.statusCode {
            case 401, 403:
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

        // Parse SSE stream: each event line starts with "data: " followed by JSON
        var contentParts: [String] = []
        let decoder = JSONDecoder()
        let ssePrefix = "data: "

        for try await line in bytes.lines {
            guard line.hasPrefix(ssePrefix) else { continue }
            let jsonString = String(line.dropFirst(ssePrefix.count))
            guard let jsonData = jsonString.data(using: .utf8) else { continue }

            do {
                let chunk = try decoder.decode(GeminiResponse.self, from: jsonData)
                if let text = chunk.candidates.first?.content.parts.first?.text {
                    contentParts.append(text)
                }
            } catch {
                // Skip malformed chunks; the stream may include keep-alive or metadata lines
                continue
            }
        }

        let content = contentParts.joined()
        guard !content.isEmpty else {
            throw ProviderError.malformedResponse(detail: "Streaming response contained no content")
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
            let response = try JSONDecoder().decode(GeminiFindingsResponse.self, from: data)
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

// MARK: - Private Request Types

private struct GeminiRequest: Encodable {
    let systemInstruction: GeminiContent?
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let responseMimeType: String
}

// MARK: - Private Response Types

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}

// MARK: - Private DTO

private struct GeminiFindingsResponse: Decodable {
    let findings: [GeminiFindingDTO]
}

private struct GeminiFindingDTO: Decodable {
    let title: String
    let description: String
    let severity: String
    let recommendation: String
    let location: String
}
