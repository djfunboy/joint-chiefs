import Foundation

/// Serializes concurrency and enforces a rolling-hour quota on Joint Chiefs reviews.
///
/// Intended for the MCP server surface, where an autonomous agent (or a runaway
/// retry loop) could otherwise drive unbounded parallel reviews and unbounded
/// cost. The CLI surface is user-initiated, one invocation per terminal command,
/// so it doesn't need this — but `ReviewRateLimiter` has no MCP dependency and
/// could be adopted elsewhere if future surfaces call for it.
///
/// Limits are passed on every `acquire` call rather than captured in `init` so
/// a single long-lived limiter tracks active/windowed state while still picking
/// up the latest `RateLimits` from `StrategyConfig` each call.
public actor ReviewRateLimiter {

    // MARK: - State

    private var activeCount: Int = 0
    /// Timestamps of successful `acquire` calls within the last rolling hour.
    /// Pruned lazily on each `acquire` to keep the array bounded by `reviewsPerHour`.
    private var recentStarts: [Date] = []
    /// Injectable clock so tests can exercise the hourly window without sleeping.
    private let now: @Sendable () -> Date

    // MARK: - Init

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    // MARK: - Public API

    /// Attempts to claim a review slot. Returns `.acquired` on success and
    /// records the start. Returns a rejection variant describing which limit
    /// was exceeded — callers use these to write an MCP error response.
    ///
    /// The caller MUST call `release()` in a `defer` after a successful
    /// acquire, regardless of whether the review succeeded, failed, or was
    /// cancelled. Otherwise the concurrency counter drifts.
    public func acquire(limits: RateLimits) -> AcquireResult {
        pruneExpired(windowSeconds: 3600)

        if activeCount >= limits.maxConcurrentReviews {
            return .rejectedConcurrent(
                active: activeCount,
                limit: limits.maxConcurrentReviews
            )
        }
        if recentStarts.count >= limits.reviewsPerHour {
            let oldest = recentStarts.first ?? now()
            let retryAfter = max(0, 3600 - now().timeIntervalSince(oldest))
            return .rejectedHourly(
                count: recentStarts.count,
                limit: limits.reviewsPerHour,
                retryAfterSeconds: Int(retryAfter.rounded(.up))
            )
        }

        activeCount += 1
        recentStarts.append(now())
        return .acquired
    }

    /// Releases the concurrency slot claimed by `acquire()`. Idempotent at the
    /// bottom — never drops below zero — so a caller can safely `defer` it
    /// without worrying about double-release in exotic error paths.
    public func release() {
        if activeCount > 0 {
            activeCount -= 1
        }
    }

    // MARK: - Observability (for tests)

    public var currentActive: Int { activeCount }
    public var currentHourly: Int {
        var window = recentStarts
        let cutoff = now().addingTimeInterval(-3600)
        window.removeAll { $0 < cutoff }
        return window.count
    }

    // MARK: - Helpers

    private func pruneExpired(windowSeconds: TimeInterval) {
        let cutoff = now().addingTimeInterval(-windowSeconds)
        recentStarts.removeAll { $0 < cutoff }
    }

    // MARK: - Acquire Result

    public enum AcquireResult: Sendable, Equatable {
        case acquired
        case rejectedConcurrent(active: Int, limit: Int)
        case rejectedHourly(count: Int, limit: Int, retryAfterSeconds: Int)

        public var rejectionMessage: String? {
            switch self {
            case .acquired:
                return nil
            case .rejectedConcurrent(let active, let limit):
                return "Joint Chiefs is already running \(active) review" +
                    (active == 1 ? "" : "s") +
                    " (limit \(limit)). Wait for the current review to finish, then retry."
            case .rejectedHourly(let count, let limit, let retryAfter):
                return "Joint Chiefs has run \(count) reviews in the last hour " +
                    "(limit \(limit)). Retry in \(retryAfter)s."
            }
        }
    }
}
