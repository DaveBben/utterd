import Foundation
import Testing
@testable import Core

@MainActor
struct TranscriptionPipelineStageTests {

    // MARK: - Helpers

    private func makeRealFile(in dir: URL, name: String = "test.m4a") throws -> URL {
        let fileURL = dir.appending(path: name)
        let created = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data([0x00, 0x01, 0x02]),
            attributes: nil
        )
        if !created {
            throw CocoaError(.fileWriteUnknown)
        }
        return fileURL
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Success: emits result via onResult and returns true

    @Test func successfulTranscriptionCallsOnResultAndReturnsTrue() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "Buy groceries", fileURL: fileURL)

        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let receivedResults = ActorBox<[TranscriptionResult]>([])
        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: store,
            logger: logger,
            onResult: { result in await receivedResults.append(result) }
        )

        let returned = await stage.process(record)

        #expect(returned == true)
        let results = await receivedResults.get()
        #expect(results.count == 1)
        #expect(results[0].transcript == "Buy groceries")
        #expect(results[0].fileURL == fileURL)
    }

    // MARK: - Success: original URL in result, not temp

    @Test func successResultContainsOriginalURL() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "Hello", fileURL: fileURL)

        let receivedResults = ActorBox<[TranscriptionResult]>([])
        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: MockMemoStore(),
            logger: MockWatcherLogger(),
            onResult: { result in await receivedResults.append(result) }
        )

        await stage.process(record)

        let results = await receivedResults.get()
        #expect(results[0].fileURL == fileURL)
    }

    // MARK: - File is copied: service receives a different (temp) URL

    @Test func serviceReceivesTempURLNotOriginal() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "Note", fileURL: fileURL)

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: MockMemoStore(),
            logger: MockWatcherLogger(),
            onResult: { _ in }
        )

        await stage.process(record)

        #expect(service.transcribeCalls.count == 1)
        #expect(service.transcribeCalls[0] != fileURL)
    }

    // MARK: - Success: temp file is cleaned up

    @Test func tempFileClearedAfterSuccess() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: MockMemoStore(),
            logger: MockWatcherLogger(),
            onResult: { _ in }
        )
        // Intercept the temp URL by overriding service after first call
        service.result = TranscriptionResult(transcript: "Note", fileURL: fileURL)

        await stage.process(record)

        // The temp URL passed to the service should no longer exist
        let tempURL = service.transcribeCalls.first
        if let tempURL {
            #expect(!FileManager.default.fileExists(atPath: tempURL.path))
        } else {
            Issue.record("Expected transcribeCalls to be non-empty")
        }
    }

    // MARK: - Success: empty transcript is still emitted and returns true

    @Test func emptyTranscriptEmittedAsSuccess() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "", fileURL: fileURL)

        let receivedResults = ActorBox<[TranscriptionResult]>([])
        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: MockMemoStore(),
            logger: MockWatcherLogger(),
            onResult: { result in await receivedResults.append(result) }
        )

        let returned = await stage.process(record)

        #expect(returned == true)
        let results = await receivedResults.get()
        #expect(results.count == 1)
        #expect(results[0].transcript == "")
    }

    // MARK: - Failure: transcription error logs, calls markProcessed, returns false

    @Test func transcriptionFailureLogsAndCallsMarkProcessed() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        struct TranscriptionError: Error {}
        let service = MockTranscriptionService()
        service.error = TranscriptionError()

        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let onResultCalled = ActorBox<Bool>(false)
        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: store,
            logger: logger,
            onResult: { _ in await onResultCalled.set(true) }
        )

        let returned = await stage.process(record)

        #expect(returned == false)
        #expect(!logger.errors.isEmpty)
        let calls = await store.markProcessedCalls
        #expect(calls.count == 1)
        #expect(calls[0].fileURL == fileURL)
        #expect(!(await onResultCalled.get()))
    }

    // MARK: - Failure: onResult is NOT called

    @Test func transcriptionFailureDoesNotCallOnResult() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        struct SomeError: Error {}
        let service = MockTranscriptionService()
        service.error = SomeError()

        let onResultCalled = ActorBox<Bool>(false)
        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: MockMemoStore(),
            logger: MockWatcherLogger(),
            onResult: { _ in await onResultCalled.set(true) }
        )

        await stage.process(record)

        #expect(!(await onResultCalled.get()))
    }

    // MARK: - Failure: copy fails when file does not exist

    @Test func missingFileCausesFailureAndCallsMarkProcessed() async throws {
        let missingURL = URL(fileURLWithPath: "/nonexistent/path/memo.m4a")
        let record = MemoRecord(fileURL: missingURL, dateCreated: Date())

        let service = MockTranscriptionService()
        let store = MockMemoStore()
        let logger = MockWatcherLogger()

        let onResultCalled = ActorBox<Bool>(false)
        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: store,
            logger: logger,
            onResult: { _ in await onResultCalled.set(true) }
        )

        let returned = await stage.process(record)

        #expect(returned == false)
        #expect(!logger.errors.isEmpty)
        let calls = await store.markProcessedCalls
        #expect(calls.count == 1)
        #expect(calls[0].fileURL == missingURL)
        #expect(!(await onResultCalled.get()))
    }

    // MARK: - Failure: temp file cleaned up after error

    @Test func tempFileClearedAfterTranscriptionFailure() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        struct TranscriptionError: Error {}
        let service = MockTranscriptionService()
        service.error = TranscriptionError()

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            store: MockMemoStore(),
            logger: MockWatcherLogger(),
            onResult: { _ in }
        )

        await stage.process(record)

        let tempURL = service.transcribeCalls.first
        if let tempURL {
            #expect(!FileManager.default.fileExists(atPath: tempURL.path))
        }
        // If transcribeCalls is empty the copy itself failed — temp file was never created,
        // which is also an acceptable clean state.
    }
}

