import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Review Rate Limiter Tests")
struct ReviewRateLimiterTests {

    /// Thread-safe mutable clock. Locked rather than actor-isolated so the
    /// limiter's `@Sendable () -> Date` closure stays synchronous.
    private final class TestClock: @unchecked Sendable {
        private var current: Date
        private let lock = NSLock()

        init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
            self.current = start
        }

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            return current
        }

        func advance(_ seconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            current = current.addingTimeInterval(seconds)
        }
    }

    private func makeLimiter(clock: TestClock) -> ReviewRateLimiter {
        ReviewRateLimiter { clock.now() }
    }

    @Test("First acquire succeeds and increments active count")
    func firstAcquireSucceeds() async {
        let limiter = makeLimiter(clock: TestClock())
        let limits = RateLimits(maxConcurrentReviews: 1, reviewsPerHour: 30)

        let result = await limiter.acquire(limits: limits)
        #expect(result == .acquired)

        let active = await limiter.currentActive
        #expect(active == 1)
    }

    @Test("Second concurrent acquire is rejected when limit is 1")
    func concurrentLimitEnforced() async {
        let limiter = makeLimiter(clock: TestClock())
        let limits = RateLimits(maxConcurrentReviews: 1, reviewsPerHour: 30)

        let first = await limiter.acquire(limits: limits)
        #expect(first == .acquired)

        let second = await limiter.acquire(limits: limits)
        if case .rejectedConcurrent(let active, let limit) = second {
            #expect(active == 1)
            #expect(limit == 1)
        } else {
            Issue.record("Expected rejectedConcurrent, got \(second)")
        }
    }

    @Test("Release allows a subsequent acquire to succeed")
    func releaseUnblocksNextAcquire() async {
        let limiter = makeLimiter(clock: TestClock())
        let limits = RateLimits(maxConcurrentReviews: 1, reviewsPerHour: 30)

        _ = await limiter.acquire(limits: limits)
        await limiter.release()
        let second = await limiter.acquire(limits: limits)
        #expect(second == .acquired)
    }

    @Test("Hourly cap rejects once reviewsPerHour is exceeded")
    func hourlyCapEnforced() async {
        let limiter = makeLimiter(clock: TestClock())
        let limits = RateLimits(maxConcurrentReviews: 100, reviewsPerHour: 3)

        for _ in 0..<3 {
            let r = await limiter.acquire(limits: limits)
            #expect(r == .acquired)
            await limiter.release()
        }

        let overflow = await limiter.acquire(limits: limits)
        if case .rejectedHourly(let count, let limit, _) = overflow {
            #expect(count == 3)
            #expect(limit == 3)
        } else {
            Issue.record("Expected rejectedHourly, got \(overflow)")
        }
    }

    @Test("Hourly cap resets after an hour elapses")
    func hourlyCapResetsOverTime() async {
        let clock = TestClock()
        let limiter = makeLimiter(clock: clock)
        let limits = RateLimits(maxConcurrentReviews: 100, reviewsPerHour: 2)

        _ = await limiter.acquire(limits: limits)
        await limiter.release()
        _ = await limiter.acquire(limits: limits)
        await limiter.release()

        // Third acquire in the same window is rejected.
        let blocked = await limiter.acquire(limits: limits)
        #expect(blocked != .acquired)

        // Advance past the hour window — earlier acquires age out.
        clock.advance(3601)

        let unblocked = await limiter.acquire(limits: limits)
        #expect(unblocked == .acquired)
    }

    @Test("Release is idempotent and never drops active below zero")
    func releaseClampsAtZero() async {
        let limiter = makeLimiter(clock: TestClock())

        await limiter.release()
        await limiter.release()
        let active = await limiter.currentActive
        #expect(active == 0)
    }

    @Test("Rejection messages are human-readable and distinguishable")
    func rejectionMessagesRender() throws {
        let concurrent = ReviewRateLimiter.AcquireResult.rejectedConcurrent(active: 1, limit: 1)
        let hourly = ReviewRateLimiter.AcquireResult.rejectedHourly(
            count: 30, limit: 30, retryAfterSeconds: 120
        )

        let concurrentMessage = try #require(concurrent.rejectionMessage)
        let hourlyMessage = try #require(hourly.rejectionMessage)

        #expect(concurrentMessage.contains("already running"))
        #expect(hourlyMessage.contains("last hour"))
        #expect(hourlyMessage.contains("120s"))
    }
}
