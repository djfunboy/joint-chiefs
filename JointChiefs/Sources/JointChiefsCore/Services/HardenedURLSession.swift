import Foundation

/// Shared `URLSession` used by every production provider. Wraps a redirect delegate
/// that strips authentication headers when a response tries to bounce the request
/// to a different host.
///
/// Why: `URLSession` has never stripped `Authorization` (or vendor equivalents like
/// `x-api-key`) on redirects. If a provider ever returns a `30x` pointing at another
/// host — a misconfigured CDN, a malicious proxy in the path, a compromised endpoint —
/// the client will happily replay the caller's API key at the new origin. The Foundation
/// default is "preserve all headers on redirect," which is the wrong default for code
/// that ships long-lived secrets in every request.
///
/// Tests inject their own `URLSession` via `URLSessionConfiguration.protocolClasses`
/// (see `MockURLProtocol`) and therefore bypass this delegate deliberately — the
/// stripper is only installed on the production shared instance.
public enum HardenedURLSession {

    /// Singleton used by `ProviderFactory`. Same configuration semantics as
    /// `URLSession.shared` with the redirect stripper installed. Safe to share
    /// across providers; the delegate is stateless.
    public static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        // Explicit delegate queue keeps redirect callbacks off the main queue without
        // forcing one-off queues per provider.
        return URLSession(
            configuration: config,
            delegate: RedirectAuthStripperDelegate(),
            delegateQueue: nil
        )
    }()
}

/// Strips credential-bearing headers from a redirect request when the target host
/// differs from the original. Same-host redirects pass through unchanged so
/// provider-internal path rewrites (common at API gateways) keep working.
final class RedirectAuthStripperDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    /// Header names that must never follow a cross-origin redirect. Covers every
    /// auth shape used by the five providers:
    /// - `Authorization` — OpenAI, Grok (Bearer tokens)
    /// - `x-api-key` / `X-Api-Key` — Anthropic
    /// - `X-Goog-Api-Key` — Gemini
    ///
    /// HTTP header names are case-insensitive; `URLRequest.setValue(nil, forHTTPHeaderField:)`
    /// removes any matching header regardless of casing, so listing both common
    /// casings is defensive rather than required.
    static let sensitiveHeaders: [String] = [
        "Authorization",
        "x-api-key",
        "X-Api-Key",
        "X-Goog-Api-Key",
    ]

    /// Returns `newRequest` with sensitive headers stripped when the redirect target
    /// host differs from the original. Same-host redirects pass through unchanged.
    /// Exposed so tests can validate the policy without driving a live redirect
    /// through URLSession.
    static func sanitize(
        newRequest: URLRequest,
        originalRequest: URLRequest?
    ) -> URLRequest {
        let originalHost = originalRequest?.url?.host?.lowercased()
        let redirectHost = newRequest.url?.host?.lowercased()
        guard originalHost != redirectHost else { return newRequest }

        var sanitized = newRequest
        for header in sensitiveHeaders {
            sanitized.setValue(nil, forHTTPHeaderField: header)
        }
        return sanitized
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Self.sanitize(
            newRequest: request,
            originalRequest: task.originalRequest
        ))
    }
}
