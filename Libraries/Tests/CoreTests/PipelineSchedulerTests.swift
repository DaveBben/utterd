import Foundation
import Testing
@testable import Core

@MainActor
struct PipelineSchedulerTests {

    // MARK: - Helpers

    private func makeRecord(
        path: String = "/memos/test.m4a",
        created: Date = Date()
    ) -> MemoRecord {
        MemoRecord(fileURL: URL(fileURLWithPath: path), dateCreated: created)
    }

    // MARK: - Handler called with oldest unprocessed record

    @Test func handlerCalledWithUnprocessedRecord() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let receivedRecord = ActorBox<MemoRecord?>(nil)
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: MockWatcherLogger(),
            handler: { rec in
                await receivedRecord.set(rec)
                return true
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(50))
        scheduler.stop()

        let received = await receivedRecord.get()
        #expect(received == record)
    }

    // MARK: - Lock held → skips and logs

    @Test func skipsWhenLockHeld() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let logger = MockWatcherLogger()
        let handlerCallCount = ActorBox<Int>(0)

        // Handler returns true (success) so lock stays held
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: logger,
            handler: { _ in
                await handlerCallCount.increment()
                return true
            }
        )

        await scheduler.start()
        // Let multiple cycles run; after first the lock is held
        try await Task.sleep(for: .milliseconds(100))
        scheduler.stop()

        // Handler should only be called once (lock prevents re-entry)
        let count = await handlerCallCount.get()
        #expect(count == 1)

        // "Lock held, skipping" should appear at least once in logs
        #expect(logger.infos.contains("Lock held, skipping"))
    }

    // MARK: - No unprocessed records → handler never called

    @Test func noActionWhenNoUnprocessedRecords() async throws {
        let store = MockMemoStore()
        // oldestUnprocessedResult stays nil

        let handlerCallCount = ActorBox<Int>(0)
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: MockWatcherLogger(),
            handler: { _ in
                await handlerCallCount.increment()
                return true
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(50))
        scheduler.stop()

        let count = await handlerCallCount.get()
        #expect(count == 0)
    }

    // MARK: - Lock resets to false on start() (crash recovery)

    @Test func lockResetOnStart() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let handlerCallCount = ActorBox<Int>(0)

        // Handler returns true, lock stays held
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: MockWatcherLogger(),
            handler: { _ in
                await handlerCallCount.increment()
                return true
            }
        )

        // Start and let one cycle run to acquire lock
        await scheduler.start()
        try await Task.sleep(for: .milliseconds(50))
        scheduler.stop()

        let countAfterFirstRun = await handlerCallCount.get()
        #expect(countAfterFirstRun == 1)

        // Restart — lock should be reset to false, allowing another handler call
        await scheduler.start()
        try await Task.sleep(for: .milliseconds(50))
        scheduler.stop()

        let countAfterSecondRun = await handlerCallCount.get()
        #expect(countAfterSecondRun == 2)
    }

    // MARK: - Repeated processing (handler called multiple times)

    @Test func handlerCalledMultipleTimes() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let callCount = ActorBox<Int>(0)

        // Return false so lock is released each cycle, enabling repeated processing
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: MockWatcherLogger(),
            handler: { _ in
                await callCount.increment()
                return false
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(200))
        scheduler.stop()

        let count = await callCount.get()
        #expect(count >= 3)
    }

    // MARK: - stop() ends the scheduling loop

    @Test func stopEndsLoop() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let callCount = ActorBox<Int>(0)

        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: MockWatcherLogger(),
            handler: { _ in
                await callCount.increment()
                return false
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(30))
        scheduler.stop()

        // Snapshot after a brief wait to let any in-flight handler call complete.
        // The loop must not fire any new cycles after the snapshot.
        try await Task.sleep(for: .milliseconds(20))
        let countAtSnapshot = await callCount.get()

        try await Task.sleep(for: .milliseconds(50))
        let countAfterWait = await callCount.get()

        #expect(countAfterWait == countAtSnapshot)
    }

    // MARK: - releaseLock() sets lock to false

    @Test func releaseLockAllowsNextCycle() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let callCount = ActorBox<Int>(0)

        // Handler returns false → releaseLock() called → next cycle can process again
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: MockWatcherLogger(),
            handler: { _ in
                let count = await callCount.increment()
                return count >= 2
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(100))
        scheduler.stop()

        let count = await callCount.get()
        #expect(count >= 2)
    }

    // MARK: - handler returns false → lock released, next record eligible

    @Test func handlerReturnsFalseLockReleased() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let handlerCallCount = ActorBox<Int>(0)
        let logger = MockWatcherLogger()

        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: logger,
            handler: { _ in
                let count = await handlerCallCount.increment()
                return count >= 3
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(200))
        scheduler.stop()

        let count = await handlerCallCount.get()
        // Handler returned false twice — lock released each time, called at least 3 times
        #expect(count >= 3)
    }

    // MARK: - Scheduler logs "Scheduler started" and "Scheduler stopped"

    @Test func logsStartAndStop() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: logger,
            handler: { _ in true }
        )

        await scheduler.start()
        scheduler.stop()

        #expect(logger.infos.contains("Scheduler started"))
        #expect(logger.infos.contains("Scheduler stopped"))
    }

    // MARK: - Handler hang triggers timeout and releases lock

    @Test func handlerThatHangsIsRecoveredByTimeout() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let logger = MockWatcherLogger()
        let handlerCallCount = ActorBox<Int>(0)

        // Handler that never returns (simulates hang).
        // With ImmediateClock the default 300s timeout fires instantly,
        // releasing the lock and allowing repeated processing.
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: logger,
            handler: { _ in
                await handlerCallCount.increment()
                try? await Task.sleep(for: .seconds(999))
                return true
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(200))
        scheduler.stop()

        // Timeout fires each cycle, so handler is called multiple times
        let count = await handlerCallCount.get()
        #expect(count >= 2)
        #expect(logger.errors.contains { $0.contains("timed out") })
    }

    // MARK: - Handler timeout releases lock

    @Test func handlerTimeoutReleasesLock() async throws {
        let store = MockMemoStore()
        let record = makeRecord()
        await store.setOldestUnprocessed(record)

        let logger = MockWatcherLogger()
        let handlerCallCount = ActorBox<Int>(0)

        // Handler hangs, but timeout is short
        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            handlerTimeout: .milliseconds(10),
            logger: logger,
            handler: { _ in
                await handlerCallCount.increment()
                try? await Task.sleep(for: .seconds(999))
                return true
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(200))
        scheduler.stop()

        // Handler should be called multiple times because timeout releases the lock
        let count = await handlerCallCount.get()
        #expect(count >= 2)
        #expect(logger.errors.contains { $0.contains("timed out") })
    }

    // MARK: - Processing log message includes file URL

    @Test func logsProcessingURL() async throws {
        let store = MockMemoStore()
        let record = makeRecord(path: "/memos/voice001.m4a")
        await store.setOldestUnprocessed(record)

        let logger = MockWatcherLogger()
        let processed = ActorBox<Bool>(false)

        let scheduler = PipelineScheduler(
            store: store,
            clock: ImmediateClock(),
            pollingInterval: .milliseconds(1),
            logger: logger,
            handler: { _ in
                await processed.set(true)
                return true
            }
        )

        await scheduler.start()
        try await Task.sleep(for: .milliseconds(50))
        scheduler.stop()

        let wasProcessed = await processed.get()
        #expect(wasProcessed)
        #expect(logger.infos.contains { $0.contains("Processing:") && $0.contains("voice001.m4a") })
    }
}

