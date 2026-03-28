import Foundation
import Testing
@testable import Core

@Suite("FSEventsDirectoryMonitor")
struct FSEventsDirectoryMonitorTests {

    @Test("Emits changed URL when file is created", .timeLimit(.minutes(1)))
    func emitsEventOnFileCreation() async throws {
        let dir = try makeWatchedDirectory()
        defer { removeDirectory(dir) }

        let monitor = FSEventsDirectoryMonitor(directoryURL: dir)
        let stream = try monitor.start()

        // Let FSEvents register before writing so we don't miss the event.
        try await Task.sleep(for: .milliseconds(200))

        let newFile = dir.appendingPathComponent("test.m4a")
        try Data("hello".utf8).write(to: newFile)

        let received = await collectFirst(from: stream, matching: { $0.contains(newFile) })

        monitor.stop()

        #expect(received != nil, "Stream should emit an event containing the new file within 10 seconds")
        #expect(received?.contains(newFile) == true)
    }

    @Test("Stream completes after stop() is called", .timeLimit(.minutes(1)))
    func streamCompletesAfterStop() async throws {
        let dir = try makeWatchedDirectory()
        defer { removeDirectory(dir) }

        let monitor = FSEventsDirectoryMonitor(directoryURL: dir)
        let stream = try monitor.start()

        monitor.stop()

        // Drain the stream — it must finish and not hang.
        for await _ in stream {}

        // Reaching here means the stream completed — that's the assertion.
    }

    @Test("Throws when directory does not exist")
    func throwsForNonexistentDirectory() throws {
        let nonexistent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let monitor = FSEventsDirectoryMonitor(directoryURL: nonexistent)

        #expect(throws: (any Error).self) {
            _ = try monitor.start()
        }
    }

    @Test("Restart returns a new functional stream", .timeLimit(.minutes(1)))
    func restartReturnsFunctionalStream() async throws {
        let dir = try makeWatchedDirectory()
        defer { removeDirectory(dir) }

        let monitor = FSEventsDirectoryMonitor(directoryURL: dir)

        // First start/stop cycle.
        let firstStream = try monitor.start()
        monitor.stop()
        for await _ in firstStream {}

        // Second start — must return a fresh, working stream.
        let secondStream = try monitor.start()

        try await Task.sleep(for: .milliseconds(200))

        let newFile = dir.appendingPathComponent("restart-test.m4a")
        try Data("world".utf8).write(to: newFile)

        let received = await collectFirst(from: secondStream, matching: { $0.contains(newFile) })

        monitor.stop()

        #expect(received != nil, "Restarted stream should emit events")
        #expect(received?.contains(newFile) == true)
    }
}

// MARK: - Helpers

// Resolves symlinks so FSEvents paths (which are always real paths) match the
// URLs constructed in tests. On macOS, /var/folders/... symlinks to
// /private/var/folders/..., and FSEvents delivers the resolved form.
private func makeWatchedDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

private func removeDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// Races a stream iteration against a 10-second timeout. Returns the first
// Set<URL> that satisfies `matching`, or nil if the timeout fires first.
private func collectFirst(
    from stream: AsyncStream<Set<URL>>,
    matching predicate: @Sendable @escaping (Set<URL>) -> Bool,
    timeout: Duration = .seconds(10)
) async -> Set<URL>? {
    await withTaskGroup(of: Set<URL>?.self) { group in
        group.addTask {
            for await urls in stream {
                if predicate(urls) { return urls }
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let result = await group.next()!
        group.cancelAll()
        return result
    }
}
