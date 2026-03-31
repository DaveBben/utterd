import Foundation
@testable import Core

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockLLMService: LLMService, @unchecked Sendable {
    nonisolated(unsafe) var result: String = ""
    nonisolated(unsafe) var error: Error?
    nonisolated(unsafe) var calls: [(systemPrompt: String, userPrompt: String)] = []

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        calls.append((systemPrompt: systemPrompt, userPrompt: userPrompt))
        if let error { throw error }
        return result
    }
}
