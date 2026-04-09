import Foundation

// MARK: - Request Types

struct ChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let responseFormat: ResponseFormat?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case responseFormat = "response_format"
    }
}

struct ResponseFormat: Encodable, Sendable {
    let type: String
    static let json = ResponseFormat(type: "json_object")
}

// MARK: - Response Types

struct ChatCompletionResponse: Decodable, Sendable {
    let id: String
    let choices: [Choice]

    struct Choice: Decodable, Sendable {
        let message: ChatMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
}

/// Represents a single streamed chunk from an OpenAI-compatible SSE response.
struct ChatCompletionChunk: Decodable, Sendable {
    let choices: [ChunkChoice]

    struct ChunkChoice: Decodable, Sendable {
        let delta: Delta

        struct Delta: Decodable, Sendable {
            let content: String?
        }
    }
}
