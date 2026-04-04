import Foundation

/// Handles the transcription step of the pipeline for a single `MemoRecord`.
///
/// Copies the audio file to a temp location, transcribes it, and returns the result.
/// On failure (file copy or transcription error), marks the record as processed
/// via `store.markProcessed` to prevent infinite re-processing.
public final class TranscriptionPipelineStage: Sendable {
    private let transcriptionService: any TranscriptionService
    private let store: any MemoStore
    private let logger: any WatcherLogger

    public init(
        transcriptionService: any TranscriptionService,
        store: any MemoStore,
        logger: any WatcherLogger
    ) {
        self.transcriptionService = transcriptionService
        self.store = store
        self.logger = logger
    }

    /// Transcribes the audio at `record.fileURL`.
    ///
    /// - Returns: The transcription result on success, or `nil` on failure.
    public func process(_ record: MemoRecord) async -> TranscriptionResult? {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).m4a")

        do {
            try FileManager.default.copyItem(at: record.fileURL, to: tempURL)
        } catch {
            logger.error("TranscriptionPipelineStage: failed to copy \(record.fileURL.lastPathComponent): \(error)")
            try? await store.markProcessed(fileURL: record.fileURL, date: Date())
            return nil
        }

        do {
            let serviceResult = try await transcriptionService.transcribe(fileURL: tempURL)
            cleanUpTempFile(at: tempURL)
            let result = TranscriptionResult(transcript: serviceResult.transcript, fileURL: record.fileURL)
            logger.info("Transcription complete for \(record.fileURL.lastPathComponent): \(result.transcript.count) characters")
            return result
        } catch {
            logger.error("TranscriptionPipelineStage: transcription failed for \(record.fileURL.lastPathComponent): \(error)")
            cleanUpTempFile(at: tempURL)
            try? await store.markProcessed(fileURL: record.fileURL, date: Date())
            return nil
        }
    }

    private func cleanUpTempFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.warning("Failed to clean up temp file \(url.lastPathComponent): \(error)")
        }
    }
}
