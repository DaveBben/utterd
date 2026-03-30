import Foundation
@testable import Core

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockTranscriptionService: TranscriptionService, @unchecked Sendable {
    nonisolated(unsafe) var result: TranscriptionResult?
    nonisolated(unsafe) var error: Error?
    nonisolated(unsafe) var transcribeCalls: [URL] = []

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        transcribeCalls.append(fileURL)
        if let error {
            throw error
        }
        return result!
    }
}
