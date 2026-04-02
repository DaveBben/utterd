import Core
import Foundation
import Testing
@testable import Utterd

// Integration tests that exercise the real FoundationModelLLMService against the on-device model.
// Requires macOS 26+ with the Foundation Model downloaded.
// Tests assert on structural properties (non-empty, valid format) rather than exact
// content, because the on-device model is non-deterministic.

@Suite("Foundation Model LLM Integration", .tags(.integration))
struct LLMIntegrationTests {

    // MARK: - Basic generation: model returns a non-empty response

    @Test("generate returns a non-empty string")
    func generateReturnsNonEmptyResponse() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let response = try await service.generate(
            systemPrompt: "You are a helpful assistant.",
            userPrompt: "Say hello in one word."
        )

        #expect(!response.isEmpty)
    }

    // MARK: - System prompt is respected: model produces relevant output

    @Test("generate produces a response related to the prompt topic")
    func generateRespectsSystemPrompt() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let response = try await service.generate(
            systemPrompt: "You are a fruit expert. Only discuss fruits.",
            userPrompt: "Name a tropical fruit."
        )

        print("Response: \(response)")
        // Structural check: model produces a short, non-empty response
        #expect(!response.isEmpty)
        #expect(response.count < 500, "Expected a short response, got \(response.count) chars")
    }

    // MARK: - Classification format: model can produce multi-line output

    @Test("generate can produce multi-line structured output")
    func generateProducesMultiLineOutput() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let response = try await service.generate(
            systemPrompt: """
            Pick the best folder for a voice memo. Reply with exactly two lines: the folder path, then a short title.

            Folders:
            - finance
            - finance.home
            - personal
            - GENERAL NOTES

            Examples:

            Transcript: "I want to save more money this year"
            finance
            Savings Goal

            Transcript: "Remember to water the plants"
            GENERAL NOTES
            Plant Watering Reminder

            Now classify this transcript. Two lines only: folder path, then title.
            """,
            userPrompt: "I need to remember to pay the electricity bill next Tuesday"
        )
        print("Response (\(response.count) chars):\n\(response)")

        let lines = response
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Model should produce at least 2 lines of non-empty text
        #expect(lines.count >= 2, "Expected 2+ lines, got \(lines.count): \(response)")
        // Both lines should be non-empty
        #expect(!lines[0].isEmpty, "First line should not be empty")
        #expect(!lines[1].isEmpty, "Second line should not be empty")
    }

    // MARK: - Summarization: model can condense text

    @Test("generate can summarize a transcript segment")
    func generateCanSummarize() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let longText = """
        Today I went to the grocery store and bought apples, bananas, oranges, \
        milk, bread, cheese, and some chicken for dinner tonight. Then I stopped \
        by the pharmacy to pick up my prescription and grabbed some vitamins. \
        After that I filled up the car with gas and got a car wash because it \
        was really dirty from the rain last week.
        """

        let response = try await service.generate(
            systemPrompt: "You are a concise summarizer. Return only the summary text.",
            userPrompt: "Summarize this transcript segment:\n\(longText)"
        )

        print("Summary (\(response.count) chars):\n\(response)")

        #expect(!response.isEmpty)
        // Summary should be shorter than the original
        #expect(response.count < longText.count, "Summary should be shorter than original")
    }
}
