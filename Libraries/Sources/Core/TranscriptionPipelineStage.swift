import Foundation

/// Handles the transcription step of the pipeline for a single `MemoRecord`.
///
/// The stage copies the audio file to a temp location, transcribes it, emits the
/// result via `onResult`, and cleans up. It does not manage the scheduler lock
/// or set `dateProcessed` on success — those are the caller's responsibility.
/// On failure (file copy or transcription error), it marks the record as processed
/// via `store.markProcessed` to prevent infinite re-processing.
public final class TranscriptionPipelineStage: Sendable {
    private let transcriptionService: any TranscriptionService
    private let store: any MemoStore
    private let logger: any WatcherLogger
    private let onResult: @Sendable (TranscriptionResult) async -> Void

    public init(
        transcriptionService: any TranscriptionService,
        store: any MemoStore,
        logger: any WatcherLogger,
        onResult: @Sendable @escaping (TranscriptionResult) async -> Void
    ) {
        self.transcriptionService = transcriptionService
        self.store = store
        self.logger = logger
        self.onResult = onResult
    }

    /// Transcribes the audio at `record.fileURL`.
    ///
    /// - Returns: `true` if transcription succeeded and `onResult` was called;
    ///   `false` if any error occurred (file copy failure, transcription error, etc.).
    @discardableResult
    public func process(_ record: MemoRecord) async -> Bool {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).m4a")

        do {
            try FileManager.default.copyItem(at: record.fileURL, to: tempURL)
        } catch {
            logger.error("TranscriptionPipelineStage: failed to copy \(record.fileURL.lastPathComponent): \(error)")
            try? await store.markProcessed(fileURL: record.fileURL, date: Date())
            return false
        }

        do {
            let serviceResult = try await transcriptionService.transcribe(fileURL: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            let result = TranscriptionResult(transcript: serviceResult.transcript, fileURL: record.fileURL)
            await onResult(result)
            return true
        } catch {
            logger.error("TranscriptionPipelineStage: transcription failed for \(record.fileURL.lastPathComponent): \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            try? await store.markProcessed(fileURL: record.fileURL, date: Date())
            return false
        }
    }
}
