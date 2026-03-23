import Testing
import Foundation
@testable import Core

@MainActor
@Suite("VoiceMemoWatcher")
struct VoiceMemoWatcherTests {

    // AC-T3-1: 3 pre-existing qualifying files cataloged at startup — only the new 4th file emits an event
    @Test("Startup files are cataloged, only new 4th file emits event")
    func startupFilesSupressedNewFileEmits() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let base = URL(fileURLWithPath: "/tmp/memos")
        let file1 = base.appending(path: "memo1.m4a")
        let file2 = base.appending(path: "memo2.m4a")
        let file3 = base.appending(path: "memo3.m4a")
        let file4 = base.appending(path: "memo4.m4a")

        fileSystem.directoryContents = [file1, file2, file3]
        fileSystem.fileSizes = [
            file1: 2048,
            file2: 2048,
            file3: 2048,
            file4: 4096,
        ]

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        var received: [VoiceMemoEvent] = []
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                received.append(event)
            }
        }

        monitor.emit([file4])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()
        await collectTask.value

        #expect(received.count == 1)
        #expect(received.first?.fileURL == file4)
    }

    // AC-T3-2: New qualifying .m4a at 2048 bytes emits exactly one event with correct URL and size
    @Test("New qualifying .m4a at 2048 bytes emits one event with correct URL and size")
    func newQualifyingFileEmitsEvent() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/recording.m4a")
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

        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()
        await collectTask.value

        #expect(received.count == 1)
        #expect(received.first == VoiceMemoEvent(fileURL: url, fileSize: 2048))
    }

    // AC-T3-3: Re-emitting the same URL at the same size produces no additional event
    @Test("Same URL at same size emits no additional event after first emission")
    func deduplicatesSameURLSameSize() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/recording.m4a")
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

        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))
        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()
        await collectTask.value

        #expect(received.count == 1)
    }

    // AC-T3-4: .txt file change produces no event
    @Test(".txt file change produces no event")
    func txtFileProducesNoEvent() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/notes.txt")
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

        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()
        await collectTask.value

        #expect(received.isEmpty)
    }

    // AC-T3-5: .m4a at 512 bytes produces no event (tracked for re-evaluation)
    @Test(".m4a at 512 bytes produces no event but is tracked for re-evaluation")
    func smallM4AProducesNoEvent() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let url = URL(fileURLWithPath: "/tmp/memos/recording.m4a")
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

        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))

        // Update size to qualifying — should emit on next notification
        fileSystem.fileSizes[url] = 2048
        monitor.emit([url])
        try? await Task.sleep(for: .milliseconds(50))

        watcher.stop()
        await collectTask.value

        // The file grew to qualifying size — expect exactly one event
        #expect(received.count == 1)
        #expect(received.first?.fileSize == 2048)
    }

    // AC-T3-6: stop() completes the stream and for-await exits
    @Test("stop() completes the event stream and for-await exits")
    func stopCompletesStream() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let logger = MockWatcherLogger()

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem, logger: logger)
        let eventStream = watcher.events()
        await watcher.start()

        var streamCompleted = false
        let collectTask = Task { @MainActor in
            for await _ in eventStream {}
            streamCompleted = true
        }

        watcher.stop()
        await collectTask.value

        #expect(streamCompleted)
    }
}
