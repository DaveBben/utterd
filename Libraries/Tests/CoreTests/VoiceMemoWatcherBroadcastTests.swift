import Testing
import Foundation
@testable import Core

@MainActor
@Suite("VoiceMemoWatcher Broadcast")
struct VoiceMemoWatcherBroadcastTests {

    // AC-T6-1: Two consumers each call events() — both receive the same event.
    @Test("Two consumers each receive the same event")
    func twoConsumersReceiveSameEvent() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let memo = URL(fileURLWithPath: "/tmp/memos/memo.m4a")
        fileSystem.fileSizes[memo] = 2048

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem)
        let stream1 = watcher.events()
        let stream2 = watcher.events()
        await watcher.start()

        var received1: [VoiceMemoEvent] = []
        var received2: [VoiceMemoEvent] = []

        let task1 = Task { @MainActor in
            for await event in stream1 { received1.append(event) }
        }
        let task2 = Task { @MainActor in
            for await event in stream2 { received2.append(event) }
        }

        monitor.emit([memo])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()

        await task1.value
        await task2.value

        #expect(received1.count == 1)
        #expect(received2.count == 1)
        #expect(received1.first?.fileURL == memo)
        #expect(received2.first?.fileURL == memo)
        #expect(received1.first?.fileSize == 2048)
        #expect(received2.first?.fileSize == 2048)
    }

    // AC-T6-2: Ordering preserved — events A then B arrive in order for each consumer.
    @Test("Two consumers receive events in order")
    func twoConsumersReceiveEventsInOrder() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let fileA = URL(fileURLWithPath: "/tmp/memos/a.m4a")
        let fileB = URL(fileURLWithPath: "/tmp/memos/b.m4a")
        fileSystem.fileSizes[fileA] = 2048
        fileSystem.fileSizes[fileB] = 3072

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem)
        let stream1 = watcher.events()
        let stream2 = watcher.events()
        await watcher.start()

        var received1: [VoiceMemoEvent] = []
        var received2: [VoiceMemoEvent] = []

        let task1 = Task { @MainActor in
            for await event in stream1 { received1.append(event) }
        }
        let task2 = Task { @MainActor in
            for await event in stream2 { received2.append(event) }
        }

        monitor.emit([fileA])
        try? await Task.sleep(for: .milliseconds(50))
        monitor.emit([fileB])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()

        await task1.value
        await task2.value

        #expect(received1.count == 2)
        #expect(received2.count == 2)
        #expect(received1[0].fileURL == fileA)
        #expect(received1[1].fileURL == fileB)
        #expect(received2[0].fileURL == fileA)
        #expect(received2[1].fileURL == fileB)
    }

    // AC-T6-3: One consumer cancels — remaining two still receive events.
    @Test("Cancelled consumer does not affect remaining consumers")
    func cancelledConsumerDoesNotAffectOthers() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let file1 = URL(fileURLWithPath: "/tmp/memos/memo1.m4a")
        let file2 = URL(fileURLWithPath: "/tmp/memos/memo2.m4a")
        fileSystem.fileSizes[file1] = 2048
        fileSystem.fileSizes[file2] = 2048

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem)
        let stream1 = watcher.events()
        let stream2 = watcher.events()
        let stream3 = watcher.events()
        await watcher.start()

        var received1: [VoiceMemoEvent] = []
        var received2: [VoiceMemoEvent] = []
        var received3: [VoiceMemoEvent] = []

        let task1 = Task { @MainActor in
            for await event in stream1 { received1.append(event) }
        }
        let task2 = Task { @MainActor in
            for await event in stream2 {
                received2.append(event)
                break // Cancel after first event
            }
        }
        let task3 = Task { @MainActor in
            for await event in stream3 { received3.append(event) }
        }

        // First event — all 3 should receive
        monitor.emit([file1])
        try? await Task.sleep(for: .milliseconds(50))

        // Wait for consumer 2 to exit
        await task2.value

        // Allow onTermination cleanup
        try? await Task.sleep(for: .milliseconds(50))

        // Second event — only consumers 1 and 3
        monitor.emit([file2])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()

        await task1.value
        await task3.value

        #expect(received1.count == 2)
        #expect(received2.count == 1)
        #expect(received3.count == 2)
    }

    // AC-T6-5: 20 files emitted at once — all 20 events reach the consumer.
    @Test("All events received when more than 16 files are emitted at once")
    func allEventsReceivedWhenBatchExceedsSixteen() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()

        let fileURLs: [URL] = (1...20).map { i in
            URL(fileURLWithPath: "/tmp/memos/memo\(i).m4a")
        }
        for url in fileURLs {
            fileSystem.fileSizes[url] = 2048
        }

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem)
        let stream = watcher.events()
        await watcher.start()

        var received: [VoiceMemoEvent] = []
        let consumerTask = Task { @MainActor in
            for await event in stream { received.append(event) }
        }

        // Emit all 20 as one batch — one slot in the monitor's buffer,
        // 20 individual yield calls on the consumer continuation.
        monitor.emit(Set(fileURLs))
        try? await Task.sleep(for: .milliseconds(100))
        watcher.stop()

        await consumerTask.value

        #expect(received.count == 20)
    }

    // AC-T6-4: Late consumer joins after 2 events — receives only the 3rd.
    @Test("Late consumer does not receive historical events")
    func lateConsumerDoesNotReceiveHistory() async {
        let monitor = MockDirectoryMonitor()
        let fileSystem = MockFileSystemChecker()
        let file1 = URL(fileURLWithPath: "/tmp/memos/memo1.m4a")
        let file2 = URL(fileURLWithPath: "/tmp/memos/memo2.m4a")
        let file3 = URL(fileURLWithPath: "/tmp/memos/memo3.m4a")
        fileSystem.fileSizes[file1] = 2048
        fileSystem.fileSizes[file2] = 2048
        fileSystem.fileSizes[file3] = 2048

        let watcher = makeWatcher(monitor: monitor, fileSystem: fileSystem)
        let earlyStream = watcher.events()
        await watcher.start()

        var earlyReceived: [VoiceMemoEvent] = []
        let earlyTask = Task { @MainActor in
            for await event in earlyStream { earlyReceived.append(event) }
        }

        // Emit 2 events before late consumer joins
        monitor.emit([file1])
        try? await Task.sleep(for: .milliseconds(50))
        monitor.emit([file2])
        try? await Task.sleep(for: .milliseconds(50))

        // Late consumer joins
        let lateStream = watcher.events()
        var lateReceived: [VoiceMemoEvent] = []
        let lateTask = Task { @MainActor in
            for await event in lateStream { lateReceived.append(event) }
        }

        // Emit 3rd event — both should get it
        monitor.emit([file3])
        try? await Task.sleep(for: .milliseconds(50))
        watcher.stop()

        await earlyTask.value
        await lateTask.value

        #expect(earlyReceived.count == 3)
        #expect(lateReceived.count == 1)
        #expect(lateReceived.first?.fileURL == file3)
    }
}
