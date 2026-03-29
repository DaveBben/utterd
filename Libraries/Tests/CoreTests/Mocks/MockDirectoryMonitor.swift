import Foundation
@testable import Core

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockDirectoryMonitor: DirectoryMonitor, @unchecked Sendable {
    nonisolated(unsafe) var failOnStart = false

    nonisolated(unsafe) private var continuation: AsyncStream<Set<URL>>.Continuation?

    func start() throws -> AsyncStream<Set<URL>> {
        if failOnStart {
            struct MonitorError: Error {}
            throw MonitorError()
        }

        let (stream, continuation) = AsyncStream<Set<URL>>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        self.continuation = continuation
        return stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
    }

    func emit(_ changedURLs: Set<URL>) {
        continuation?.yield(changedURLs)
    }

    func completeStream() {
        continuation?.finish()
        continuation = nil
    }
}
