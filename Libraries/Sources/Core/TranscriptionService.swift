import Foundation

/// Abstracts speech-to-text transcription so tests can inject a mock.
public protocol TranscriptionService: Sendable {
    func transcribe(fileURL: URL) async throws -> TranscriptionResult
}
