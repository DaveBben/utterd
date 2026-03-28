import Testing
import Foundation
@testable import Core

@MainActor
@Suite("VoiceMemoWatcher Folder Availability")
struct VoiceMemoWatcherFolderTests {

    // AC-T5-1: existsResult = false at start → no crash, warnings contains folder path
    // start() logs the warning synchronously (before creating monitorTask), so it is
    // visible immediately after start() returns.
    @Test("Missing folder at start logs warning containing folder path")
    func missingFolderLogsWarning() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()
        let directoryURL = URL(fileURLWithPath: "/tmp/memos")

        fileSystem.existsResult = false

        // After 2nd check the folder appears — allows the monitorTask to exit its polling
        // loop so stop() cancels cleanly without leaving a dangling task.
        fileSystem.onDirectoryExistsCheck = { count in
            if count >= 2 {
                fileSystem.existsResult = true
                fileSystem.readableResult = true
            }
        }

        let watcher = VoiceMemoWatcher(
            directoryURL: directoryURL,
            monitor: monitor,
            fileSystem: fileSystem,
            logger: logger,
            clock: ImmediateClock()
        )
        _ = watcher.events()
        await watcher.start()

        // Warning must already be present — start() logs it synchronously before
        // creating the monitorTask.
        let pathInWarning = logger.warnings.contains { $0.contains(directoryURL.path) }
        #expect(!logger.warnings.isEmpty)
        #expect(pathInWarning)

        watcher.stop()
    }

    // AC-T5-2: Polling for missing folder — folder appears after 2nd check → "monitoring started"
    // logged and a subsequent file event is delivered to the consumer.
    @Test("Polling loop recovers: folder appears after 2nd check, monitoring starts, event delivered")
    func pollingLoopRecoversWhenFolderAppears() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()
        let directoryURL = URL(fileURLWithPath: "/tmp/memos")

        fileSystem.existsResult = false
        fileSystem.readableResult = true

        // After 2nd directoryExists check, the folder appears.
        fileSystem.onDirectoryExistsCheck = { count in
            if count >= 2 {
                fileSystem.existsResult = true
                fileSystem.readableResult = true
            }
        }

        let fileURL = directoryURL.appending(path: "memo.m4a")
        fileSystem.fileSizes[fileURL] = 2048

        let watcher = VoiceMemoWatcher(
            directoryURL: directoryURL,
            monitor: monitor,
            fileSystem: fileSystem,
            logger: logger,
            clock: ImmediateClock()
        )
        let eventStream = watcher.events()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        await watcher.start()

        // Yield enough times for the monitorTask to advance through its polling loop
        // and reach the monitoring state. ImmediateClock means each poll iteration
        // is just a single cooperative yield.
        for _ in 0..<20 {
            await Task.yield()
        }

        let hasMonitoringStarted = logger.infos.contains { $0.contains("monitoring started") }
        #expect(hasMonitoringStarted)

        // Verify the monitoring pipeline is operational.
        monitor.emit([fileURL])
        for _ in 0..<10 {
            await Task.yield()
        }

        watcher.stop()
        await collectTask.value

        #expect(received.count == 1)
        #expect(received.first?.fileURL == fileURL)
    }

    // AC-T5-3: Folder disappears mid-operation — stream ends + existsResult false → error logged.
    // Verified via the recovery test (AC-T5-4) which confirms the full cycle:
    // monitoring → stream ends → error logged → recovery. This test checks just the
    // error logging portion using directoryExistsCallCount to detect the post-stream check.
    @Test("Stream completion with missing folder logs error and does not crash",
          .timeLimit(.minutes(1)))
    func streamCompletionWithMissingFolderLogsError() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()
        let directoryURL = URL(fileURLWithPath: "/tmp/memos")

        fileSystem.existsResult = true
        fileSystem.readableResult = true

        let watcher = VoiceMemoWatcher(
            directoryURL: directoryURL,
            monitor: monitor,
            fileSystem: fileSystem,
            logger: logger,
            clock: ImmediateClock()
        )
        _ = watcher.events()

        await watcher.start()

        // Yield to let monitorTask enter the for-await loop.
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate the folder disappearing and the FSEvents stream ending.
        fileSystem.existsResult = false
        // After recovery check, make folder available so polling exits.
        fileSystem.onDirectoryExistsCheck = { count in
            if count >= 3 {
                fileSystem.existsResult = true
                fileSystem.readableResult = true
            }
        }
        monitor.completeStream()

        // Wait for the monitorTask to process the stream end and enter the recovery path.
        // The key indicator is directoryExistsCallCount increasing (the post-stream check).
        let deadline = ContinuousClock.now + .seconds(5)
        while fileSystem.directoryExistsCallCount < 3 && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        watcher.stop()

        // The error should have been logged when directoryExists returned false
        // after the stream ended.
        #expect(!logger.errors.isEmpty, "Expected error log after folder disappeared; directoryExistsCallCount=\(fileSystem.directoryExistsCallCount)")
    }

    // AC-T5-4: After deletion + polling recovery → monitoring resumes, "monitoring started"
    // re-logged, and a file event is delivered.
    @Test("Monitoring resumes after folder deletion and reappearance")
    func monitoringResumesAfterFolderDeletionAndReappearance() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()
        let directoryURL = URL(fileURLWithPath: "/tmp/memos")

        fileSystem.existsResult = true
        fileSystem.readableResult = true

        let fileURL = directoryURL.appending(path: "recovered.m4a")
        fileSystem.fileSizes[fileURL] = 2048

        let watcher = VoiceMemoWatcher(
            directoryURL: directoryURL,
            monitor: monitor,
            fileSystem: fileSystem,
            logger: logger,
            clock: ImmediateClock()
        )
        let eventStream = watcher.events()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        await watcher.start()
        for _ in 0..<10 {
            await Task.yield()
        }

        // First "monitoring started" should appear after normal startup.
        let firstStartCount = logger.infos.filter { $0.contains("monitoring started") }.count
        #expect(firstStartCount >= 1)

        // Simulate folder disappearing and stream ending.
        fileSystem.existsResult = false

        // After 2nd poll check (from recovery), folder reappears.
        fileSystem.directoryExistsCallCount = 0
        fileSystem.onDirectoryExistsCheck = { count in
            if count >= 2 {
                fileSystem.existsResult = true
                fileSystem.readableResult = true
            }
        }

        monitor.completeStream()

        // Yield to let the recovery flow execute: detect disappearance, log error,
        // re-enter polling, poll twice, reappear, log "monitoring started" again.
        for _ in 0..<30 {
            await Task.yield()
        }

        let errorLogged = !logger.errors.isEmpty
        #expect(errorLogged)

        let totalMonitorStartCount = logger.infos.filter { $0.contains("monitoring started") }.count
        #expect(totalMonitorStartCount >= 2)

        // Inject a file event after recovery to confirm the pipeline is live.
        monitor.emit([fileURL])
        for _ in 0..<10 {
            await Task.yield()
        }

        watcher.stop()
        await collectTask.value

        #expect(received.contains { $0.fileURL == fileURL })
    }

    // AC-T5-5: Exists but not readable → error logged containing permission/read indicator,
    // no file events emitted.
    @Test("Unreadable folder logs permission error and emits no events")
    func unreadableFolderLogsPermissionError() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()
        let directoryURL = URL(fileURLWithPath: "/tmp/memos")

        fileSystem.existsResult = true
        fileSystem.readableResult = false

        // After 2nd check, grant read permission so polling can terminate cleanly.
        fileSystem.onDirectoryExistsCheck = { count in
            if count >= 2 {
                fileSystem.readableResult = true
            }
        }

        let watcher = VoiceMemoWatcher(
            directoryURL: directoryURL,
            monitor: monitor,
            fileSystem: fileSystem,
            logger: logger,
            clock: ImmediateClock()
        )
        let eventStream = watcher.events()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        await watcher.start()
        // Error must already be present — start() logs it synchronously.
        #expect(!logger.errors.isEmpty)
        #expect(received.isEmpty)

        watcher.stop()
        await collectTask.value
    }

    // AC-T5-6: Permission error resolves after 2nd check → "monitoring started" logged.
    @Test("Monitoring starts after permission is granted on 2nd poll")
    func monitoringStartsAfterPermissionGranted() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()
        let directoryURL = URL(fileURLWithPath: "/tmp/memos")

        fileSystem.existsResult = true
        fileSystem.readableResult = false

        // After 2nd directoryExists check, grant read permission.
        fileSystem.onDirectoryExistsCheck = { count in
            if count >= 2 {
                fileSystem.readableResult = true
            }
        }

        let watcher = VoiceMemoWatcher(
            directoryURL: directoryURL,
            monitor: monitor,
            fileSystem: fileSystem,
            logger: logger,
            clock: ImmediateClock()
        )
        _ = watcher.events()

        await watcher.start()

        // Yield enough times for the monitorTask to poll twice and reach monitoring state.
        for _ in 0..<20 {
            await Task.yield()
        }

        let hasMonitoringStarted = logger.infos.contains { $0.contains("monitoring started") }
        #expect(hasMonitoringStarted)

        watcher.stop()
    }
}
