import Foundation

typealias MockRequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

/// Routes mock responses by URL host so concurrent test suites (e.g. OpenAI vs.
/// Anthropic) don't overwrite each other's handlers via a single shared slot.
/// Setting `requestHandler` registers the handler for the next request's host —
/// existing call sites continue to work because each suite uses a distinct host.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlersByHost: [String: MockRequestHandler] = [:]
    nonisolated(unsafe) private static var fallbackHandler: MockRequestHandler?
    nonisolated(unsafe) private static var bodiesByHost: [String: Data] = [:]
    nonisolated(unsafe) private static var fallbackLastBody: Data?

    /// Last body sent through the fallback (non-host-keyed) handler. Tests using
    /// host-keyed handlers should read `lastRequestBody(forHost:)` instead.
    static var lastRequestBody: Data? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return fallbackLastBody
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            fallbackLastBody = newValue
        }
    }

    static func lastRequestBody(forHost host: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return bodiesByHost[host]
    }

    /// Setter remains a single static property for backwards compatibility with
    /// existing tests. The first request after assignment binds the handler to
    /// that request's host; subsequent requests to other hosts fall through to
    /// the per-host map (or the most-recently-set fallback).
    static var requestHandler: MockRequestHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return fallbackHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            fallbackHandler = newValue
        }
    }

    /// Explicitly register a handler for a given host. Use this when a test's
    /// requests must not race with other suites' fallback handlers.
    static func setHandler(forHost host: String, _ handler: @escaping MockRequestHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlersByHost[host] = handler
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlersByHost.removeAll()
        fallbackHandler = nil
        bodiesByHost.removeAll()
        fallbackLastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // Capture the body from the stream since URLSession clears httpBody
        var capturedBody: Data?
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let bytesRead = stream.read(buffer, maxLength: 4096)
                guard bytesRead > 0 else { break }
                data.append(buffer, count: bytesRead)
            }
            stream.close()
            capturedBody = data
        } else if let body = request.httpBody {
            capturedBody = body
        }

        let resolution = Self.resolveHandler(for: request)
        if let body = capturedBody {
            Self.recordBody(body, host: request.url?.host, usedFallback: resolution.usedFallback)
        }

        guard let handler = resolution.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func resolveHandler(for request: URLRequest) -> (handler: MockRequestHandler?, usedFallback: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let host = request.url?.host, let handler = handlersByHost[host] {
            return (handler, false)
        }
        return (fallbackHandler, true)
    }

    private static func recordBody(_ body: Data, host: String?, usedFallback: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let host {
            bodiesByHost[host] = body
        }
        if usedFallback {
            fallbackLastBody = body
        }
    }
}
