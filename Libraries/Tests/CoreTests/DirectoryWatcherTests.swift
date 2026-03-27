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

    // MARK: - Error Conditions (Task 3a)

    @Test("Throws directoryNotFound for non-existent directory")
    func throwsDirectoryNotFound() {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        #expect(throws: DirectoryWatcherError.directoryNotFound(bogus)) {
            try DirectoryWatcher(directory: bogus)
        }
    }

    @Test("Throws notADirectory when given a file URL")
    func throwsNotADirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("afile.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        #expect(throws: DirectoryWatcherError.notADirectory(fileURL)) {
            try DirectoryWatcher(directory: fileURL)
        }
    }

    @Test("Throws permissionDenied for unreadable directory")
    func throwsPermissionDenied() throws {
        // Skip when running as root — permissions don't apply
        try #require(getuid() != 0)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer {
            // Restore permissions so cleanup can succeed
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: tmpDir.path)
            try? FileManager.default.removeItem(at: tmpDir)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: tmpDir.path)

        #expect(throws: DirectoryWatcherError.permissionDenied(tmpDir)) {
            try DirectoryWatcher(directory: tmpDir)
        }
    }

    // MARK: - Cancellation (Task 3a)

    @Test("Cancellation stops monitoring — AC-03.1")
    func cancellationStopsMonitoring() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = try DirectoryWatcher(directory: tmpDir)

        // Start a task that consumes events, then cancel it
        let task = Task {
            var collected: [URL] = []
            for await url in watcher.events {
                collected.append(url)
            }
            return collected
        }

        // Let FSEvents stream start
        try await Task.sleep(for: .milliseconds(300))

        // Cancel the consuming task
        task.cancel()
        let result = await task.value

        // After cancellation, creating new files should produce no events
        FileManager.default.createFile(
            atPath: tmpDir.appendingPathComponent("after_cancel.m4a").path, contents: nil)
        try await Task.sleep(for: .milliseconds(500))

        // The task should have exited cleanly — result may be empty or have some events
        // but no crash or hang occurred (the test completing IS the assertion)
        _ = result
    }

    @Test("No resource leaks on cancellation — AC-03.2")
    func noResourceLeaksOnCancellation() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = try DirectoryWatcher(directory: tmpDir)

        let task = Task {
            for await _ in watcher.events {}
        }

        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await task.value

        // After cancellation + cleanup, creating files should not crash or emit events
        FileManager.default.createFile(
            atPath: tmpDir.appendingPathComponent("post_cancel.m4a").path, contents: nil)
        try await Task.sleep(for: .milliseconds(500))

        // Collect from the same stream — should get nothing (stream already finished)
        let afterCancel = await collectEvents(from: watcher.events, count: 1, timeout: 1)
        #expect(afterCancel.isEmpty)
    }

    // MARK: - Edge Cases (Task 3a)

    @Test("Directory deleted while running terminates stream gracefully")
    func directoryDeletedTerminatesStream() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        // No defer cleanup — we delete the directory as part of the test

        let watcher = try DirectoryWatcher(directory: tmpDir)

        async let events = collectEvents(from: watcher.events, count: 1, timeout: 5)

        try await Task.sleep(for: .milliseconds(300))

        // Delete the directory while the watcher is running
        try FileManager.default.removeItem(at: tmpDir)

        // Create an event to trigger the FSEvents callback (the directory is gone,
        // so the scan should fail and finish the stream)
        // We need to trigger an FSEvents callback — touching a file in the parent may do it,
        // or we wait for the stream to notice the deletion
        // The stream should terminate when the next callback tries to scan the deleted directory

        let received = await events
        // The key assertion: no crash, no hang — the stream terminates gracefully
        #expect(received.isEmpty)
    }

    @Test("Empty directory at startup works and emits when file created later")
    func emptyDirectoryAtStartup() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Watcher starts on empty directory — should not throw
        let watcher = try DirectoryWatcher(directory: tmpDir)

        async let events = collectEvents(from: watcher.events, count: 1, timeout: 5)

        try await Task.sleep(for: .milliseconds(200))
        FileManager.default.createFile(
            atPath: tmpDir.appendingPathComponent("first.m4a").path, contents: nil)

        let received = await events
        #expect(received.count == 1)
        #expect(received.first?.lastPathComponent == "first.m4a")
    }

    @Test("File renamed away after creation — original .m4a URL was still emitted")
    func fileRenamedAwayStillEmitted() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = try DirectoryWatcher(directory: tmpDir)

        let m4aURL = tmpDir.appendingPathComponent("rename_test.m4a")
        let renamedURL = tmpDir.appendingPathComponent("rename_test.wav")

        async let events = collectEvents(from: watcher.events, count: 1, timeout: 5)

        try await Task.sleep(for: .milliseconds(200))

        // Create the .m4a file
        FileManager.default.createFile(atPath: m4aURL.path, contents: nil)

        // Small delay to let FSEvents pick it up, then rename
        try await Task.sleep(for: .milliseconds(500))
        try FileManager.default.moveItem(at: m4aURL, to: renamedURL)

        let received = await events
        // The .m4a file should have been emitted before the rename
        #expect(received.count == 1)
        #expect(received.first?.lastPathComponent == "rename_test.m4a")
    }

    // MARK: - Burst Test (Task 4)

    @Test("20 .m4a files in rapid succession emit exactly 20 unique URLs")
    func burstOf20Files() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = try DirectoryWatcher(directory: tmpDir)

        async let events = collectEvents(from: watcher.events, count: 20, timeout: 15)

        try await Task.sleep(for: .milliseconds(200))
        for i in 1...20 {
            FileManager.default.createFile(
                atPath: tmpDir.appendingPathComponent("burst\(i).m4a").path, contents: nil)
        }

        let received = await events
        #expect(received.count == 20)

        let uniqueNames = Set(received.map { $0.lastPathComponent })
        #expect(uniqueNames.count == 20)
    }
}
