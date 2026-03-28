/// A clock that resolves `sleep(for:)` immediately (after yielding for cooperative scheduling)
/// while using `ContinuousClock.Instant` as its instant type.
/// Used in tests to eliminate real-time waits in polling loops.
struct ImmediateClock: Clock {
    typealias Instant = ContinuousClock.Instant
    typealias Duration = Swift.Duration

    var now: Instant {
        ContinuousClock().now
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}
