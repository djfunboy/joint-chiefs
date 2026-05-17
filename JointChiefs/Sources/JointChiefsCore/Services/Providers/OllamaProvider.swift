import Foundation

/// Calls the Ollama REST API to perform code reviews and participate in debate rounds using local LLM models.
public struct OllamaProvider: ReviewProvider {

    // MARK: - Properties

    public let name: String
    public let model: String
    public let providerType: ProviderType = .ollama
    private let endpoint: URL
    private let urlSession: URLSession
    private let requestTimeout: TimeInterval

    // MARK: - Init

    /// Creates an Ollama provider for local LLM inference.
    ///
    /// - Parameters:
    ///   - model: The model identifier to use. Defaults to `"llama3"`.
    ///   - endpoint: The base URL for the Ollama server. Defaults to `http://localhost:11434`.
    ///   - timeoutSeconds: Per-request timeout. Applied to both the `api/tags` probe
    ///     (`testConnection`) and the streaming `api/chat` call. Defaults to 600s (10 minutes).
    ///     Large local models (e.g. 70B) need real time for first-token latency —
    ///     model load into VRAM alone can exceed the 60s `URLRequest` default.
    ///   - urlSession: The URL session to use for requests. Defaults to `.shared`.
    public init(
        model: String = "llama3",
        endpoint: URL = URL(string: "http://localhost:11434")!,
        timeoutSeconds: Int = 600,
        urlSession: URLSession = .shared
    ) {
        self.name = "Ollama"
        self.model = model
        self.endpoint = endpoint
        self.requestTimeout = TimeInterval(timeoutSeconds)
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
            OllamaChatMessage(role: "system", content: systemPrompt),
            OllamaChatMessage(role: "user", content: userMessage),
        ]

        let (content, findings) = try await sendRequest(messages: messages, formatJSON: true)
        return ProviderReview(providerName: name, model: model, content: content, findings: findings)
    }

    public func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview {
        let systemPrompt = ReviewPrompts.debateSystem(round: round, priorFindings: priorFindings)

        let userMessage = "Code under review:\n\n```\n\(code)\n```\n\nRespond with your positions on each finding above."

        let messages = [
            OllamaChatMessage(role: "system", content: systemPrompt),
            OllamaChatMessage(role: "user", content: userMessage),
        ]

        let (content, findings) = try await sendRequest(messages: messages, formatJSON: true)
        return ProviderReview(providerName: name, model: model, content: content, findings: findings)
    }

    public func testConnection() async throws -> Bool {
        let requestURL = endpoint.appendingPathComponent("api/tags")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost
            || urlError.code == .networkConnectionLost {
            throw ProviderError.networkError(underlying: "Ollama server is not running at \(endpoint.absoluteString)")
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw ProviderError.timeout
        } catch let urlError as URLError {
            throw ProviderError.networkError(underlying: urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse(detail: "Response was not an HTTP response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return true
    }

    // MARK: - Private Methods

    /// Sends a streaming chat request to the Ollama API.
    ///
    /// Each line of the response is a JSON object with `message.content` containing a token.
    /// The final line has `done: true`. All content tokens are concatenated into the full response.
    ///
    /// - Parameters:
    ///   - messages: The chat messages to send.
    ///   - formatJSON: Whether to request JSON-formatted output from Ollama.
    /// - Returns: A tuple of the raw content string and parsed findings.
    /// - Throws: `ProviderError` for server errors, network issues, or malformed responses.
    private func sendRequest(
        messages: [OllamaChatMessage],
        formatJSON: Bool
    ) async throws -> (String, [Finding]) {
        let requestURL = endpoint.appendingPathComponent("api/chat")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        let body = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: true,
            format: formatJSON ? "json" : nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await urlSession.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost
            || urlError.code == .networkConnectionLost {
            throw ProviderError.networkError(underlying: "Ollama server is not running at \(endpoint.absoluteString)")
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
            case 500...599:
                throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
            default:
                throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        }

        // Parse streaming response: each line is a JSON object with message.content
        var contentParts: [String] = []
        let decoder = JSONDecoder()

        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let chunk = try decoder.decode(OllamaStreamChunk.self, from: lineData)
                if let text = chunk.message?.content, !text.isEmpty {
                    contentParts.append(text)
                }
                if chunk.done { break }
            } catch {
                throw ProviderError.malformedResponse(
                    detail: "Failed to decode Ollama stream chunk: \(error.localizedDescription)"
                )
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
            let response = try JSONDecoder().decode(OllamaFindingsResponse.self, from: data)
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

// MARK: - Ollama API Types

private struct OllamaChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

private struct OllamaChatRequest: Encodable, Sendable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let format: String?
}

private struct OllamaChatResponse: Decodable, Sendable {
    let message: OllamaChatMessage
    let done: Bool
}

private struct OllamaStreamChunk: Decodable {
    let message: OllamaChatMessage?
    let done: Bool
}

private struct OllamaFindingsResponse: Decodable {
    let findings: [OllamaFindingDTO]
}

private struct OllamaFindingDTO: Decodable {
    let title: String
    let description: String
    let severity: String
    let recommendation: String
    let location: String
}
