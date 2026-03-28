import Foundation

/// Abstracts filesystem directory monitoring so tests can inject a mock
/// instead of relying on real FSEvents.
public protocol DirectoryMonitor: Sendable {
    /// Begins monitoring and returns a fresh async stream of changed file URLs.
    /// Each call creates a new stream — required for recovery flows where the
    /// monitor is stopped and restarted. Throws if the directory does not exist.
    func start() throws -> AsyncStream<Set<URL>>

    /// Stops monitoring and finishes the stream returned by ``start()``.
    func stop()
}
