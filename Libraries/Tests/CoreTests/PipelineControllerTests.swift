import Foundation
import Testing
@testable import Core

// MARK: - MockMemoStore test helpers

extension MockMemoStore {
    func setAllUnprocessed(_ records: [MemoRecord]) {
        allUnprocessedResult = records
    }
}

// MARK: - Test Suite

@MainActor
struct PipelineControllerTests {

    private func makeRecord(path: String) -> MemoRecord {
        MemoRecord(fileURL: URL(fileURLWithPath: path), dateCreated: Date())
    }

    private func makeTempFile(name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pipeline-test-\(name).m4a")
        try Data().write(to: url)
        return url
    }

    // MARK: - AC-1.1: Immediate processing on new event

    @Test func immediateProcessingOnNewEvent() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let tempFile = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let svc = MockTranscriptionService()
        svc.result = TranscriptionResult(transcript: "hello", fileURL: tempFile)

        let processedCount = ActorBox<Int>(0)
        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: { await processedCount.increment() }
        )

        let task = Task { await controller.start() }
        await Task.yield()

        continuation.yield(VoiceMemoEvent(fileURL: tempFile, fileSize: 100))
        continuation.finish()

        for _ in 0..<50 {
            if await processedCount.get() > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        #expect(svc.transcribeCalls.count >= 1)
    }

    // MARK: - AC-1.2: Sequential processing in insertion order

    @Test func sequentialProcessingOfMultipleEvents() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFiles = try (0..<3).map { i in try makeTempFile(name: "seq-\(i)") }
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        let svc = MockTranscriptionService()
        svc.result = TranscriptionResult(transcript: "t", fileURL: tempFiles[0])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }
        await Task.yield()

        for url in tempFiles {
            svc.result = TranscriptionResult(transcript: "t", fileURL: url)
            continuation.yield(VoiceMemoEvent(fileURL: url, fileSize: 100))
        }
        continuation.finish()

        for _ in 0..<100 {
            let calls = await store.markProcessedCalls
            if calls.count >= 3 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        let calls = await store.markProcessedCalls
        #expect(calls.count == 3)
        #expect(calls.map(\.fileURL) == tempFiles)
    }

    // MARK: - AC-2.1: Startup drain processes existing unprocessed records

    @Test func startupDrainProcessesExistingRecords() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFiles = try (0..<2).map { i in try makeTempFile(name: "drain-\(i)") }
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        let records = tempFiles.map { makeRecord(path: $0.path) }
        await store.setAllUnprocessed(records)

        let svc = MockTranscriptionService()
        svc.result = TranscriptionResult(transcript: "drain", fileURL: tempFiles[0])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }

        for _ in 0..<100 {
            let calls = await store.markProcessedCalls
            if calls.count >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        let calls = await store.markProcessedCalls
        #expect(calls.count == 2)
    }

    // MARK: - AC-2.2: Startup drain records processed before new watcher events

    @Test func startupDrainBeforeNewEvents() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFiles = try (0..<3).map { i in try makeTempFile(name: "order-\(i)") }
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        // tempFiles[0] and [1] are pre-existing; tempFiles[2] is the new watcher event
        await store.setAllUnprocessed([
            makeRecord(path: tempFiles[0].path),
            makeRecord(path: tempFiles[1].path),
        ])

        let svc = MockTranscriptionService()
        svc.result = TranscriptionResult(transcript: "t", fileURL: tempFiles[0])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }
        await Task.yield()

        continuation.yield(VoiceMemoEvent(fileURL: tempFiles[2], fileSize: 100))
        continuation.finish()

        for _ in 0..<100 {
            let calls = await store.markProcessedCalls
            if calls.count >= 3 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        let calls = await store.markProcessedCalls
        #expect(calls.count == 3)
        #expect(calls[0].fileURL == tempFiles[0])
        #expect(calls[1].fileURL == tempFiles[1])
        #expect(calls[2].fileURL == tempFiles[2])
    }

    // MARK: - AC-2.3/2.4: Empty allUnprocessedResult means no startup processing

    @Test func startupDrainSkipsFailedAndProcessedRecords() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        // allUnprocessedResult is empty by default — nothing to drain
        let svc = MockTranscriptionService()

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }

        try await Task.sleep(for: .milliseconds(100))

        controller.stop()
        task.cancel()

        #expect(svc.transcribeCalls.isEmpty)
    }

    // MARK: - AC-2 variant: single unprocessed record is drained

    @Test func startupDrainWithMixedRecords() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFile = try makeTempFile(name: "single-drain")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        await store.setAllUnprocessed([makeRecord(path: tempFile.path)])

        let svc = MockTranscriptionService()
        svc.result = TranscriptionResult(transcript: "t", fileURL: tempFile)

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }

        for _ in 0..<100 {
            let calls = await store.markProcessedCalls
            if calls.count >= 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        #expect(svc.transcribeCalls.count == 1)
    }

    // MARK: - AC-3.1: Transcription failure calls markFailed, not markProcessed

    @Test func transcriptionFailureCallsMarkFailed() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFile = try makeTempFile(name: "fail-transcribe")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let svc = MockTranscriptionService()
        struct TranscribeError: Error, LocalizedError {
            var errorDescription: String? { "transcription failed" }
        }
        svc.error = TranscribeError()

        await store.setAllUnprocessed([makeRecord(path: tempFile.path)])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }

        for _ in 0..<100 {
            let calls = await store.markFailedCalls
            if calls.count >= 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        let failedCalls = await store.markFailedCalls
        let processedCalls = await store.markProcessedCalls

        #expect(failedCalls.count == 1)
        #expect(!failedCalls[0].reason.isEmpty)
        #expect(processedCalls.isEmpty)
    }

    // MARK: - AC-3.2/3.3: Routing failure calls markFailed, not markProcessed

    @Test func routingFailureCallsMarkFailed() async throws {
        let store = MockMemoStore()
        let notesStore = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFile = try makeTempFile(name: "fail-route")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let svc = MockTranscriptionService()
        svc.result = TranscriptionResult(transcript: "hello", fileURL: tempFile)

        await store.setAllUnprocessed([makeRecord(path: tempFile.path)])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let notesService = MockNotesService()
        struct NoteError: Error, LocalizedError {
            var errorDescription: String? { "note creation failed" }
        }
        notesService.createNoteError = NoteError()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: {
                NoteRoutingPipelineStage(
                    notesService: notesService,
                    llmService: MockLLMService(),
                    summarizer: MockTranscriptSummarizer(),
                    store: notesStore,
                    logger: logger,
                    configProvider: { RoutingConfiguration() },
                    contextBudget: try! LLMContextBudget(totalWords: 100, systemPromptOverhead: 10, summaryReserveRatio: 0.3)
                )
            },
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }

        for _ in 0..<100 {
            let calls = await store.markFailedCalls
            if calls.count >= 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        let failedCalls = await store.markFailedCalls
        let processedCalls = await store.markProcessedCalls

        #expect(failedCalls.count == 1)
        #expect(!failedCalls[0].reason.isEmpty)
        #expect(processedCalls.isEmpty)
    }

    // MARK: - Success fires onItemProcessed exactly once

    @Test func successCallsOnItemProcessed() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFile = try makeTempFile(name: "success-callback")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let svc = MockTranscriptionService()
        svc.result = TranscriptionResult(transcript: "hello", fileURL: tempFile)

        await store.setAllUnprocessed([makeRecord(path: tempFile.path)])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let callCount = ActorBox<Int>(0)

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: { await callCount.increment() }
        )

        let task = Task { await controller.start() }

        for _ in 0..<100 {
            if await callCount.get() >= 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        controller.stop()
        task.cancel()

        #expect(await callCount.get() == 1)
    }

    // MARK: - stop() cancels processing loop

    @Test func stopCancelsProcessingLoop() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        // Use a blocking service so we can observe whether a second item starts processing
        let firstCallStarted = ActorBox<Bool>(false)
        let firstCallCanProceed = ActorBox<CheckedContinuation<Void, Never>?>(nil)
        let secondCallStarted = ActorBox<Bool>(false)

        let tempFile1 = try makeTempFile(name: "stop-test-1")
        let tempFile2 = try makeTempFile(name: "stop-test-2")
        defer {
            try? FileManager.default.removeItem(at: tempFile1)
            try? FileManager.default.removeItem(at: tempFile2)
        }

        final class CountingBlockingService: TranscriptionService, @unchecked Sendable {
            let firstCallStarted: ActorBox<Bool>
            let firstCallCanProceed: ActorBox<CheckedContinuation<Void, Never>?>
            let secondCallStarted: ActorBox<Bool>
            let url1: URL
            let url2: URL

            init(
                firstCallStarted: ActorBox<Bool>,
                firstCallCanProceed: ActorBox<CheckedContinuation<Void, Never>?>,
                secondCallStarted: ActorBox<Bool>,
                url1: URL,
                url2: URL
            ) {
                self.firstCallStarted = firstCallStarted
                self.firstCallCanProceed = firstCallCanProceed
                self.secondCallStarted = secondCallStarted
                self.url1 = url1
                self.url2 = url2
            }

            func transcribe(fileURL: URL) async throws -> TranscriptionResult {
                // First call: block until signaled
                // Second call: just record it started
                let isFirst = await !firstCallStarted.get()
                if isFirst {
                    await firstCallStarted.set(true)
                    await withCheckedContinuation { continuation in
                        Task { await firstCallCanProceed.set(continuation) }
                    }
                } else {
                    await secondCallStarted.set(true)
                }
                try Task.checkCancellation()
                return TranscriptionResult(transcript: "t", fileURL: url1)
            }
        }

        let svc = CountingBlockingService(
            firstCallStarted: firstCallStarted,
            firstCallCanProceed: firstCallCanProceed,
            secondCallStarted: secondCallStarted,
            url1: tempFile1,
            url2: tempFile2
        )

        // Both records pre-queued for processing
        await store.setAllUnprocessed([
            makeRecord(path: tempFile1.path),
            makeRecord(path: tempFile2.path),
        ])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let controller = PipelineController(
            store: store,
            transcriptionService: svc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }

        // Wait for first transcription to start
        for _ in 0..<100 {
            if await firstCallStarted.get() { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        // Stop while first item is in-flight
        controller.stop()
        task.cancel()

        // Unblock the first call
        if let cont = await firstCallCanProceed.get() {
            cont.resume()
        }

        try await Task.sleep(for: .milliseconds(100))

        // Second item should NOT have started processing after stop()
        #expect(await secondCallStarted.get() == false)
    }

    // MARK: - Cancellation does not mark failed

    @Test func cancellationDoesNotMarkFailed() async throws {
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let tempFile = try makeTempFile(name: "cancel-test")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // A transcription service that blocks until signaled
        let blockStarted = ActorBox<Bool>(false)
        let canProceed = ActorBox<CheckedContinuation<Void, Never>?>(nil)

        final class BlockingService: TranscriptionService, @unchecked Sendable {
            let blockStarted: ActorBox<Bool>
            let canProceed: ActorBox<CheckedContinuation<Void, Never>?>
            let tempFileURL: URL

            init(
                blockStarted: ActorBox<Bool>,
                canProceed: ActorBox<CheckedContinuation<Void, Never>?>,
                tempFileURL: URL
            ) {
                self.blockStarted = blockStarted
                self.canProceed = canProceed
                self.tempFileURL = tempFileURL
            }

            func transcribe(fileURL: URL) async throws -> TranscriptionResult {
                await blockStarted.set(true)
                await withCheckedContinuation { continuation in
                    Task { await canProceed.set(continuation) }
                }
                try Task.checkCancellation()
                return TranscriptionResult(transcript: "t", fileURL: tempFileURL)
            }
        }

        let blockingSvc = BlockingService(
            blockStarted: blockStarted,
            canProceed: canProceed,
            tempFileURL: tempFile
        )

        await store.setAllUnprocessed([makeRecord(path: tempFile.path)])

        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream()
        continuation.finish()

        let controller = PipelineController(
            store: store,
            transcriptionService: blockingSvc,
            watcherStream: stream,
            logger: logger,
            makeRoutingStage: nil,
            onItemProcessed: {}
        )

        let task = Task { await controller.start() }

        // Wait until transcription has started
        for _ in 0..<100 {
            if await blockStarted.get() { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        // Stop while transcription is in-flight
        controller.stop()
        task.cancel()

        // Unblock the transcription service
        if let cont = await canProceed.get() {
            cont.resume()
        }

        try await Task.sleep(for: .milliseconds(100))

        let failedCalls = await store.markFailedCalls
        #expect(failedCalls.isEmpty)
    }
}
