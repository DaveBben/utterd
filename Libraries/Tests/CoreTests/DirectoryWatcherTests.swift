import Foundation
import Testing
@testable import Core

// MARK: - Test Helper

/// Collect up to `count` events from the stream, waiting at most `timeout` seconds total.
///
/// Uses structured concurrency: a child task collects from the stream; a sibling task
/// enforces the deadline. Whichever finishes first wins — the other is cancelled.
func collectEvents(from stream: AsyncStream<URL>, count: Int, timeout: TimeInterval) async -> [URL] {
    await withTaskGroup(of: [URL].self) { group in
        // Collector task: iterate the stream until count reached
        group.addTask {
            var collected: [URL] = []
            for await url in stream {
                collected.append(url)
                if collected.count >= count {
                    break
                }
            }
            return collected
        }

        // Timeout task: sleep then return empty to trigger cancellation
        group.addTask {
            try? await Task.sleep(for: .seconds(timeout))
            return []
        }

        // Take the first result (whichever task finishes first)
        var result: [URL] = []
        if let first = await group.next() {
            result = first
        }
        // Cancel the remaining task
        group.cancelAll()
        return result
    }
}

// MARK: - Tests

@Suite("DirectoryWatcher")
struct DirectoryWatcherTests {

    // MARK: AC-01.1 — New .m4a file detected within 5s

    @Test("New .m4a file is detected within 5 seconds")
    func detectsNewM4AFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = try DirectoryWatcher(directory: tmpDir)
        let fileURL = tmpDir.appendingPathComponent("test.m4a")

        async let events = collectEvents(from: watcher.events, count: 1, timeout: 5)

        // Small delay to let FSEvents stream start
        try await Task.sleep(for: .milliseconds(200))
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        let received = await events
        #expect(received.count == 1)
        #expect(received.first?.lastPathComponent == "test.m4a")
    }

    // MARK: AC-01.2 — Non-.m4a files are ignored

    @Test("Non-.m4a files are not emitted")
    func ignoresNonM4AFiles() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = try DirectoryWatcher(directory: tmpDir)

        async let events = collectEvents(from: watcher.events, count: 1, timeout: 2)

        try await Task.sleep(for: .milliseconds(200))
        FileManager.default.createFile(
            atPath: tmpDir.appendingPathComponent("notes.json").path, contents: nil)
        FileManager.default.createFile(
            atPath: tmpDir.appendingPathComponent("image.png").path, contents: nil)
        FileManager.default.createFile(
            atPath: tmpDir.appendingPathComponent("README.txt").path, contents: nil)

        let received = await events
        #expect(received.isEmpty)
    }

    // MARK: AC-01.3 — 5 .m4a files in quick succession → exactly 5 unique URLs

    @Test("5 .m4a files in quick succession emit exactly 5 unique URLs")
    func detectsFiveFilesInSuccession() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = try DirectoryWatcher(directory: tmpDir)

        async let events = collectEvents(from: watcher.events, count: 5, timeout: 10)

        try await Task.sleep(for: .milliseconds(200))
        for i in 1...5 {
            FileManager.default.createFile(
                atPath: tmpDir.appendingPathComponent("memo\(i).m4a").path, contents: nil)
        }

        let received = await events
        #expect(received.count == 5)

        let uniqueURLs = Set(received.map { $0.lastPathComponent })
        #expect(uniqueURLs.count == 5)
    }

    // MARK: AC-02.1 — Pre-existing .m4a files are ignored; new ones are detected

    @Test("Pre-existing .m4a files are ignored; new file after watcher start is detected")
    func ignoresPreExistingFilesAndDetectsNew() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create 3 pre-existing .m4a files before the watcher is created
        for i in 1...3 {
            FileManager.default.createFile(
                atPath: tmpDir.appendingPathComponent("existing\(i).m4a").path, contents: nil)
        }

        // First: verify no events are emitted for pre-existing files
        let watcher1 = try DirectoryWatcher(directory: tmpDir)
        let preExisting = await collectEvents(from: watcher1.events, count: 1, timeout: 1)
        #expect(preExisting.isEmpty)

        // Then create a new file and verify it IS detected
        let watcher2 = try DirectoryWatcher(directory: tmpDir)
        let newFileURL = tmpDir.appendingPathComponent("new.m4a")

        async let newEvents = collectEvents(from: watcher2.events, count: 1, timeout: 5)
        try await Task.sleep(for: .milliseconds(200))
        FileManager.default.createFile(atPath: newFileURL.path, contents: nil)

        let received = await newEvents
        #expect(received.count == 1)
        #expect(received.first?.lastPathComponent == "new.m4a")
    }
}
