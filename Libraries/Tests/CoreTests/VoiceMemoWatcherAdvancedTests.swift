import Testing
import Foundation
@testable import Core

@MainActor
@Suite("VoiceMemoWatcher Advanced")
struct VoiceMemoWatcherAdvancedTests {

    // AC-T4a-1: File cataloged at 512 bytes (nil in seen-set), grows to 2048 → exactly one event
    @Test("Mid-sync file grows from 512 to 2048 bytes and emits exactly one event")
    func midSyncFileGrowsAndEmits() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/memo.m4a")
        // At startup: file exists at 512 bytes — below threshold, stored as nil in seen-set
        fileSystem.directoryContents = [url]
        fileSystem.fileSizes = [url: 512]

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        // File has now grown to qualifying size
        fileSystem.fileSizes[url] = 2048
        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))

        watcher.stop()
        await collectTask.value

        #expect(received.count == 1)
        #expect(received.first == VoiceMemoEvent(fileURL: url, fileSize: 2048))
    }

    // AC-T4a-2: After emission at 2048, re-emitting same URL at same size → no additional event
    @Test("Already-emitted file URL at same size produces no additional event")
    func alreadyEmittedFileNoAdditionalEvent() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/memo.m4a")
        fileSystem.fileSizes = [url: 2048]

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        // First emission
        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))
        // Re-emit same URL at same size
        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))

        watcher.stop()
        await collectTask.value

        #expect(received.count == 1)
    }

    // AC-T4a-3: 5 separate notifications for 5 distinct files → exactly 5 events
    @Test("5 separate notifications for 5 distinct files emit exactly 5 events")
    func burstOfFiveDistinctFilesEmitsFiveEvents() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let base = URL(fileURLWithPath: "/tmp/memos")
        let urls = (1...5).map { base.appending(path: "memo\($0).m4a") }
        for url in urls {
            fileSystem.fileSizes[url] = 2048
        }

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        for url in urls {
            monitor.emit([url])
        }
        try? await Task.sleep(for: .milliseconds(100))

        watcher.stop()
        await collectTask.value

        #expect(received.count == 5)
        let receivedURLs = Set(received.map(\.fileURL))
        #expect(receivedURLs == Set(urls))
    }

    // AC-T4a-4: Logger contains file name and size after event emission
    @Test("Logger infos contains file name and size after event emission")
    func loggerContainsFileNameAndSize() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/memo.m4a")
        fileSystem.fileSizes = [url: 3072]

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        let collectTask = Task { @MainActor in
            for await _ in eventStream {}
        }

        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))

        watcher.stop()
        await collectTask.value

        let hasFileName = logger.infos.contains { $0.contains("memo.m4a") }
        let hasSize = logger.infos.contains { $0.contains("3072") }
        #expect(hasFileName)
        #expect(hasSize)
    }

    // AC-T4a-5: fileSize returns nil (deletion) → no crash, no error log
    @Test("fileSize nil (deletion) causes no crash and no error log")
    func deletedFileCausesNoCrashNoErrorLog() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/memo.m4a")
        // File exists in seen-set at startup
        fileSystem.directoryContents = [url]
        fileSystem.fileSizes = [url: 2048]

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        // Simulate deletion — fileSize returns nil
        fileSystem.fileSizes.removeValue(forKey: url)
        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))

        watcher.stop()
        await collectTask.value

        #expect(received.isEmpty)
        #expect(logger.errors.isEmpty)
    }

    // AC-T4a-6: .memo.m4a.icloud placeholder in seen-set, then real memo.m4a at 2048 → one event
    @Test("iCloud placeholder replaced by real file emits exactly one event for real file")
    func iCloudPlaceholderReplacedByRealFile() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let base = URL(fileURLWithPath: "/tmp/memos")
        let placeholder = base.appending(path: ".memo.m4a.icloud")
        let realFile = base.appending(path: "memo.m4a")

        // Startup: only the placeholder exists
        fileSystem.directoryContents = [placeholder]
        fileSystem.fileSizes = [placeholder: 200]

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        // iCloud sync completes: real file appears at 2048 bytes
        fileSystem.fileSizes[realFile] = 2048
        monitor.emit([realFile])
        try? await Task.sleep(for: .milliseconds(50))

        watcher.stop()
        await collectTask.value

        #expect(received.count == 1)
        #expect(received.first?.fileURL == realFile)
        #expect(received.first?.fileSize == 2048)
    }
}
