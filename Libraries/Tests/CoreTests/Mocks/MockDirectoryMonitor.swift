import Foundation
@testable import Core

/// A test double for `DirectoryMonitor` that lets tests inject synthetic
/// filesystem change notifications.
final class MockDirectoryMonitor: DirectoryMonitor, @unchecked Sendable {
    /// When `true`, `start()` throws an error.
    var failOnStart: Bool = false

    private let continuation: AsyncStream<Set<URL>>.Continuation
    let events: AsyncStream<Set<URL>>

    init() {
        var captured: AsyncStream<Set<URL>>.Continuation!
        events = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {
        if failOnStart {
            throw MockMonitorError.startFailed
        }
    }

    func stop() {
        continuation.finish()
    }

    /// Yield a set of changed URLs into the event stream.
    func emit(_ changedURLs: Set<URL>) {
        continuation.yield(changedURLs)
    }

    /// Finish the async stream, signaling no more events.
    func completeStream() {
        continuation.finish()
    }
}

enum MockMonitorError: Error {
    case startFailed
}
