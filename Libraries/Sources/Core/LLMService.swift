import Foundation

/// Abstracts language model generation so tests can inject a mock.
public protocol LLMService: Sendable {
    func generate(systemPrompt: String, userPrompt: String) async throws -> String
}
