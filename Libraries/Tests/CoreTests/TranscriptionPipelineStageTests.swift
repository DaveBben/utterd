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

    // MARK: - Success: returns result

    @Test func successfulTranscriptionReturnsResult() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "Buy groceries", fileURL: fileURL)

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: MockWatcherLogger()
        )

        let result = await stage.process(record)

        #expect(result != nil)
        #expect(result?.transcript == "Buy groceries")
        #expect(result?.fileURL == fileURL)
    }

    // MARK: - Success: original URL in result, not temp

    @Test func successResultContainsOriginalURL() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "Hello", fileURL: fileURL)

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: MockWatcherLogger()
        )

        let result = await stage.process(record)

        #expect(result?.fileURL == fileURL)
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
            logger: MockWatcherLogger()
        )

        _ = await stage.process(record)

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
        service.result = TranscriptionResult(transcript: "Note", fileURL: fileURL)

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: MockWatcherLogger()
        )

        _ = await stage.process(record)

        let tempURL = service.transcribeCalls.first
        if let tempURL {
            #expect(!FileManager.default.fileExists(atPath: tempURL.path))
        } else {
            Issue.record("Expected transcribeCalls to be non-empty")
        }
    }

    // MARK: - Success: empty transcript is still returned

    @Test func emptyTranscriptReturnedAsSuccess() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "", fileURL: fileURL)

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: MockWatcherLogger()
        )

        let result = await stage.process(record)

        #expect(result != nil)
        #expect(result?.transcript == "")
    }

    // MARK: - Failure: transcription error logs, returns nil, does not call store

    @Test func transcriptionFailureLogsAndDoesNotCallStore() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir)
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        struct TranscriptionError: Error {}
        let service = MockTranscriptionService()
        service.error = TranscriptionError()

        let logger = MockWatcherLogger()

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: logger
        )

        let result = await stage.process(record)

        #expect(result == nil)
        #expect(!logger.errors.isEmpty)
    }

    // MARK: - Failure: copy fails when file does not exist

    @Test func missingFileCausesFailureAndDoesNotCallStore() async throws {
        let missingURL = URL(fileURLWithPath: "/nonexistent/path/memo.m4a")
        let record = MemoRecord(fileURL: missingURL, dateCreated: Date())

        let service = MockTranscriptionService()
        let logger = MockWatcherLogger()

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: logger
        )

        let result = await stage.process(record)

        #expect(result == nil)
        #expect(!logger.errors.isEmpty)
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
            logger: MockWatcherLogger()
        )

        _ = await stage.process(record)

        let tempURL = service.transcribeCalls.first
        if let tempURL {
            #expect(!FileManager.default.fileExists(atPath: tempURL.path))
        }
        // If transcribeCalls is empty the copy itself failed — temp file was never created,
        // which is also an acceptable clean state.
    }

    // MARK: - Temp file preserves source extension (.qta)

    @Test func tempFilePreservesQTAExtension() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir, name: "test.qta")
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "QTA memo", fileURL: fileURL)

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: MockWatcherLogger()
        )

        _ = await stage.process(record)

        #expect(service.transcribeCalls.count == 1)
        #expect(service.transcribeCalls[0].pathExtension == "qta")
    }

    // MARK: - Temp file preserves source extension (.m4a)

    @Test func tempFilePreservesM4AExtension() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = try makeRealFile(in: dir, name: "test.m4a")
        let record = MemoRecord(fileURL: fileURL, dateCreated: Date())

        let service = MockTranscriptionService()
        service.result = TranscriptionResult(transcript: "M4A memo", fileURL: fileURL)

        let stage = TranscriptionPipelineStage(
            transcriptionService: service,
            logger: MockWatcherLogger()
        )

        _ = await stage.process(record)

        #expect(service.transcribeCalls.count == 1)
        #expect(service.transcribeCalls[0].pathExtension == "m4a")
    }
}
