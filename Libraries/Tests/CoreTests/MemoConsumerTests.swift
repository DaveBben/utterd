import Foundation
import Testing
@testable import Core

@MainActor
struct MemoConsumerTests {
    let fixedDate = Date(timeIntervalSince1970: 1_736_935_200) // 2026-01-15T10:00:00Z
    let memoURL = URL(filePath: "/memos/abc.m4a")

    func makeStream(events: [VoiceMemoEvent]) -> AsyncStream<VoiceMemoEvent> {
        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
        return stream
    }

    @Test func newEventInsertsRecordWithMatchingFields() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let consumer = MemoConsumer(store: store, logger: logger, now: { self.fixedDate })

        let event = VoiceMemoEvent(fileURL: memoURL, fileSize: 1000)
        await consumer.consume(makeStream(events: [event]))

        let records = await store.insertedRecords
        #expect(records.count == 1)
        #expect(records[0].fileURL == memoURL)
        #expect(records[0].dateCreated == fixedDate)
        #expect(records[0].dateProcessed == nil)
    }

    @Test func duplicateEventIsIgnored() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let consumer = MemoConsumer(store: store, logger: logger, now: { self.fixedDate })

        let event = VoiceMemoEvent(fileURL: memoURL, fileSize: 1000)

        // Process once to populate the store
        await consumer.consume(makeStream(events: [event]))
        // Process same URL again
        await consumer.consume(makeStream(events: [event]))

        let records = await store.insertedRecords
        #expect(records.count == 1)
    }

    @Test func insertFailureIsLoggedAndDoesNotCrash() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        struct StoreWriteError: Error {}
        await store.setInsertError(StoreWriteError())

        let consumer = MemoConsumer(store: store, logger: logger, now: { self.fixedDate })

        let event = VoiceMemoEvent(fileURL: memoURL, fileSize: 1000)
        await consumer.consume(makeStream(events: [event]))

        #expect(logger.errors.count == 1)
    }

    @Test func multipleEventsAreAllProcessed() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let consumer = MemoConsumer(store: store, logger: logger, now: { self.fixedDate })

        let urls = [
            URL(filePath: "/memos/a.m4a"),
            URL(filePath: "/memos/b.m4a"),
            URL(filePath: "/memos/c.m4a"),
        ]
        let events = urls.map { VoiceMemoEvent(fileURL: $0, fileSize: 500) }
        await consumer.consume(makeStream(events: events))

        let records = await store.insertedRecords
        #expect(records.count == 3)
        #expect(Set(records.map(\.fileURL)) == Set(urls))
    }

    @Test func insertFailureDoesNotStopSubsequentEvents() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        struct StoreWriteError: Error {}
        await store.setInsertError(StoreWriteError())

        let consumer = MemoConsumer(store: store, logger: logger, now: { self.fixedDate })

        let urls = [
            URL(filePath: "/memos/x.m4a"),
            URL(filePath: "/memos/y.m4a"),
        ]
        let events = urls.map { VoiceMemoEvent(fileURL: $0, fileSize: 500) }
        await consumer.consume(makeStream(events: events))

        // Both events should have been attempted and logged
        #expect(logger.errors.count == 2)
    }

    @Test func memoConsumerCallsOnRecordInserted() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let receivedRecords = ActorBox<[MemoRecord]>([])

        let consumer = MemoConsumer(
            store: store,
            logger: logger,
            now: { self.fixedDate },
            onRecordInserted: { record in
                Task { await receivedRecords.append(record) }
            }
        )

        let event = VoiceMemoEvent(fileURL: memoURL, fileSize: 1000)
        await consumer.consume(makeStream(events: [event]))

        // Yield to allow the callback Task to complete
        await Task.yield()

        let received = await receivedRecords.get()
        #expect(received.count == 1)
        #expect(received[0].fileURL == memoURL)
    }

    @Test func onRecordInsertedNotCalledOnInsertFailure() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let callCount = ActorBox<Int>(0)

        struct StoreWriteError: Error {}
        await store.setInsertError(StoreWriteError())

        let consumer = MemoConsumer(
            store: store,
            logger: logger,
            now: { self.fixedDate },
            onRecordInserted: { _ in
                Task { await callCount.increment() }
            }
        )

        let event = VoiceMemoEvent(fileURL: memoURL, fileSize: 1000)
        await consumer.consume(makeStream(events: [event]))

        await Task.yield()

        #expect(await callCount.get() == 0)
    }
}
