import Foundation
@testable import Core

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockTranscriptSummarizer: TranscriptSummarizer, @unchecked Sendable {
    nonisolated(unsafe) var result: String = ""
    nonisolated(unsafe) var error: Error?
    nonisolated(unsafe) var calls: [(transcript: String, contextBudget: LLMContextBudget)] = []

    func summarize(transcript: String, contextBudget: LLMContextBudget) async throws -> String {
        calls.append((transcript: transcript, contextBudget: contextBudget))
        if let error { throw error }
        return result
    }
}
