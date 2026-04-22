import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Hardened URLSession Tests")
struct HardenedURLSessionTests {

    private func makeRequest(
        url: String,
        authHeaders: [String: String] = [:]
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        for (field, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    @Test("Cross-origin redirect strips Authorization header")
    func crossOriginStripsAuthorization() {
        let original = makeRequest(
            url: "https://api.openai.com/v1/chat/completions",
            authHeaders: ["Authorization": "Bearer sk-secret"]
        )
        let redirect = makeRequest(
            url: "https://attacker.example.com/v1/chat/completions",
            authHeaders: ["Authorization": "Bearer sk-secret"]
        )
        let sanitized = RedirectAuthStripperDelegate.sanitize(
            newRequest: redirect,
            originalRequest: original
        )
        #expect(sanitized.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Cross-origin redirect strips Anthropic x-api-key header")
    func crossOriginStripsXAPIKey() {
        let original = makeRequest(
            url: "https://api.anthropic.com/v1/messages",
            authHeaders: ["x-api-key": "sk-ant-secret"]
        )
        let redirect = makeRequest(
            url: "https://evil.example.com/v1/messages",
            authHeaders: ["x-api-key": "sk-ant-secret"]
        )
        let sanitized = RedirectAuthStripperDelegate.sanitize(
            newRequest: redirect,
            originalRequest: original
        )
        #expect(sanitized.value(forHTTPHeaderField: "x-api-key") == nil)
        #expect(sanitized.value(forHTTPHeaderField: "X-Api-Key") == nil)
    }

    @Test("Cross-origin redirect strips Gemini X-Goog-Api-Key header")
    func crossOriginStripsGoogApiKey() {
        let original = makeRequest(
            url: "https://generativelanguage.googleapis.com/v1/models",
            authHeaders: ["X-Goog-Api-Key": "AIza-secret"]
        )
        let redirect = makeRequest(
            url: "https://evil.example.com/v1/models",
            authHeaders: ["X-Goog-Api-Key": "AIza-secret"]
        )
        let sanitized = RedirectAuthStripperDelegate.sanitize(
            newRequest: redirect,
            originalRequest: original
        )
        #expect(sanitized.value(forHTTPHeaderField: "X-Goog-Api-Key") == nil)
    }

    @Test("Same-origin redirect preserves Authorization header")
    func sameOriginPreservesAuthorization() {
        let original = makeRequest(
            url: "https://api.openai.com/v1/chat/completions",
            authHeaders: ["Authorization": "Bearer sk-secret"]
        )
        let redirect = makeRequest(
            url: "https://api.openai.com/v2/chat/completions",
            authHeaders: ["Authorization": "Bearer sk-secret"]
        )
        let sanitized = RedirectAuthStripperDelegate.sanitize(
            newRequest: redirect,
            originalRequest: original
        )
        #expect(sanitized.value(forHTTPHeaderField: "Authorization") == "Bearer sk-secret")
    }

    @Test("Cross-origin redirect preserves non-auth headers")
    func crossOriginPreservesNonAuthHeaders() {
        let original = makeRequest(
            url: "https://api.openai.com/v1/chat/completions",
            authHeaders: [
                "Authorization": "Bearer sk-secret",
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
            ]
        )
        let redirect = makeRequest(
            url: "https://attacker.example.com/",
            authHeaders: [
                "Authorization": "Bearer sk-secret",
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
            ]
        )
        let sanitized = RedirectAuthStripperDelegate.sanitize(
            newRequest: redirect,
            originalRequest: original
        )
        #expect(sanitized.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sanitized.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sanitized.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test("Host comparison is case-insensitive")
    func sameHostCaseInsensitive() {
        let original = makeRequest(
            url: "https://API.OpenAI.com/v1/chat/completions",
            authHeaders: ["Authorization": "Bearer sk-secret"]
        )
        let redirect = makeRequest(
            url: "https://api.openai.com/v1/chat/completions",
            authHeaders: ["Authorization": "Bearer sk-secret"]
        )
        let sanitized = RedirectAuthStripperDelegate.sanitize(
            newRequest: redirect,
            originalRequest: original
        )
        // Same host modulo case — must preserve the header.
        #expect(sanitized.value(forHTTPHeaderField: "Authorization") == "Bearer sk-secret")
    }

    @Test("Shared hardened session is accessible and reusable")
    func sharedSessionExists() {
        let session1 = HardenedURLSession.shared
        let session2 = HardenedURLSession.shared
        // Same instance across accesses — the delegate is not re-instantiated per call.
        #expect(session1 === session2)
    }
}
