import Foundation

/// Thin wrapper that lets Joint Chiefs treat any OpenAI-compatible local
/// inference server (LM Studio, Jan, llama.cpp-server, Msty, LocalAI, etc.) as
/// a first-class spoke in the debate panel.
///
/// The protocol is identical to OpenAI's own — same `/v1/chat/completions`
/// endpoint, same SSE streaming format, same JSON request/response shape — so
/// we delegate to `OpenAIProvider` with the user-configured endpoint, model,
/// and (typically empty) API key. The only reason this isn't just a different
/// configuration of `OpenAIProvider` is that we need a distinct `providerType`
/// so weights, per-provider model overrides, and debate attribution don't
/// collide with cloud OpenAI. A user running cloud GPT AND LM Studio wants
/// both as independent panel seats.
public struct OpenAICompatibleProvider: ReviewProvider {

    // MARK: - Properties

    public let name: String
    public let model: String
    public let providerType: ProviderType = .openAICompatible
    private let inner: OpenAIProvider

    // MARK: - Init

    /// Creates an OpenAI-compatible provider pointing at a local inference server.
    ///
    /// - Parameters:
    ///   - endpoint: The server's base URL, ending in `/v1`. LM Studio default
    ///     is `http://localhost:1234/v1`.
    ///   - model: The model identifier the server exposes (as shown in the
    ///     response of `GET /v1/models`).
    ///   - apiKey: Bearer token. Empty string is fine — most local servers
    ///     don't validate it. Hosted OpenAI-compatible services (Together, Groq,
    ///     anyscale, etc.) will require a real key here.
    ///   - timeoutSeconds: Per-request timeout. Defaults to 600s (10 min) to
    ///     match the Ollama path — local models need real time for first-token
    ///     latency, especially on first invocation after a cold model load.
    ///   - displayName: What the panel calls this spoke — "LM Studio", "Jan",
    ///     "llama.cpp", etc. Purely cosmetic; the orchestrator anonymizes
    ///     identities during the final synthesis regardless.
    public init(
        endpoint: URL,
        model: String,
        apiKey: String = "",
        timeoutSeconds: Int = 600,
        displayName: String = "LM Studio"
    ) {
        self.name = displayName
        self.model = model
        // Build a URLSession with the caller-configured timeout so the streaming
        // `/v1/chat/completions` call gets minutes instead of the 60s URLRequest
        // default — same reasoning as the Ollama timeout fix.
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = TimeInterval(timeoutSeconds)
        sessionConfig.timeoutIntervalForResource = TimeInterval(timeoutSeconds * 2)
        let session = URLSession(configuration: sessionConfig)
        self.inner = OpenAIProvider(
            apiKey: apiKey,
            model: model,
            endpoint: endpoint,
            urlSession: session
        )
    }

    // MARK: - ReviewProvider

    public func review(code: String, context: ReviewContext) async throws -> ProviderReview {
        let underlying = try await inner.review(code: code, context: context)
        // Replace the provider-name stamp so panel attribution reads "LM Studio"
        // (or whatever preset the user picked), not "OpenAI".
        return ProviderReview(
            providerName: name,
            model: model,
            content: underlying.content,
            findings: underlying.findings
        )
    }

    public func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview {
        let underlying = try await inner.debate(code: code, priorFindings: priorFindings, round: round)
        return ProviderReview(
            providerName: name,
            model: model,
            content: underlying.content,
            findings: underlying.findings
        )
    }

    public func testConnection() async throws -> Bool {
        try await inner.testConnection()
    }
}
