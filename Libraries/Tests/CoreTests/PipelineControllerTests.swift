import Foundation
import Testing
@testable import Core

@MainActor
struct PipelineControllerTests {

    // MARK: - Helpers

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeRealFile(in dir: URL, name: String = "voice.m4a") throws -> URL {
        let fileURL = dir.appending(path: name)
        let created = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data([0x00, 0x01, 0x02]),
            attributes: nil
        )
        if !created { throw CocoaError(.fileWriteUnknown) }
        return fileURL
    }

    private func makeEmptyStream() -> AsyncStream<VoiceMemoEvent> {
        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()
        return stream
    }

    // MARK: - Stage.process is called with unprocessed record

    @Test func schedulerCallsStageProcessWithUnprocessedRecord() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let store = MockMemoStore()
        await store.setOldestUnprocessed(record)

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "hello", fileURL: fileURL)

        let logger = MockWatcherLogger()

        let controller = PipelineController(
            store: store,
            transcriptionService: service,
            watcherStream: makeEmptyStream(),
            logger: logger,
            clock: ImmediateClock()
        )

        await controller.start()
        try await Task.sleep(for: .milliseconds(100))
        controller.stop()

        #expect(service.transcribeCalls.count >= 1)
    }

    // MARK: - On transcription failure, lock is released (next cycle processes again)

    @Test func transcriptionFailureReleasesLock() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let store = MockMemoStore()
        await store.setOldestUnprocessed(record)

        struct TranscriptionError: Error {}
        let service = MockTranscriptionService()
        service.error = TranscriptionError()

        let logger = MockWatcherLogger()

        let controller = PipelineController(
            store: store,
            transcriptionService: service,
            watcherStream: makeEmptyStream(),
            logger: logger,
            clock: ImmediateClock()
        )

        await controller.start()
        try await Task.sleep(for: .milliseconds(100))
        controller.stop()

        // When lock is released after each failure, the scheduler can cycle again
        // so transcribe should be called more than once
        #expect(service.transcribeCalls.count >= 2)
    }

    // MARK: - On transcription success, lock stays held (skipping log appears)

    @Test func transcriptionSuccessKeepsLockHeld() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let store = MockMemoStore()
        await store.setOldestUnprocessed(record)

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "done", fileURL: fileURL)

        let logger = MockWatcherLogger()

        let controller = PipelineController(
            store: store,
            transcriptionService: service,
            watcherStream: makeEmptyStream(),
            logger: logger,
            clock: ImmediateClock()
        )

        await controller.start()
        try await Task.sleep(for: .milliseconds(100))
        controller.stop()

        // Success returns true → lock stays held → subsequent cycles log "Lock held, skipping"
        #expect(logger.infos.contains("Lock held, skipping"))
        // Transcription should only be called once (lock prevents re-entry)
        #expect(service.transcribeCalls.count == 1)
    }

    // MARK: - onResult logs "awaiting stage 2"

    @Test func onResultLogsAwaitingStage2() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let store = MockMemoStore()
        await store.setOldestUnprocessed(record)

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "note to self", fileURL: fileURL)

        let logger = MockWatcherLogger()

        let controller = PipelineController(
            store: store,
            transcriptionService: service,
            watcherStream: makeEmptyStream(),
            logger: logger,
            clock: ImmediateClock()
        )

        await controller.start()
        try await Task.sleep(for: .milliseconds(100))
        controller.stop()

        #expect(logger.infos.contains { $0.contains("awaiting stage 2") })
    }

    // MARK: - stop() stops scheduler and consumer

    @Test func stopHaltsScheduler() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let store = MockMemoStore()
        await store.setOldestUnprocessed(record)

        struct TranscriptionError: Error {}
        let service = MockTranscriptionService()
        service.error = TranscriptionError()

        let logger = MockWatcherLogger()

        let controller = PipelineController(
            store: store,
            transcriptionService: service,
            watcherStream: makeEmptyStream(),
            logger: logger,
            clock: ImmediateClock()
        )

        await controller.start()
        try await Task.sleep(for: .milliseconds(50))
        controller.stop()

        // Snapshot the call count shortly after stop
        try await Task.sleep(for: .milliseconds(20))
        let countAtStop = service.transcribeCalls.count

        // Wait longer — no new calls should happen after stop
        try await Task.sleep(for: .milliseconds(100))
        let countAfterWait = service.transcribeCalls.count

        #expect(countAfterWait == countAtStop)
        #expect(logger.infos.contains("Scheduler stopped"))
    }
}
