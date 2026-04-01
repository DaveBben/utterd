import Core
import Foundation
import Testing
@testable import Utterd

// Integration tests that exercise the real FoundationModelLLMService against the on-device model.
// Requires macOS 26+ with the Foundation Model downloaded.
// Tests skip at runtime on older macOS via the requireModelAccess() guard.

private func requireModelAccess() async throws {
    guard #available(macOS 26, *) else {
        try #require(Bool(false), "Requires macOS 26+ — skipping")
        return
    }
    let service = FoundationModelLLMService()
    do {
        _ = try await service.generate(systemPrompt: "Respond with: ok", userPrompt: "test")
    } catch {
        Issue.record("Foundation Model is not available — model may not be downloaded. Error: \(error)")
        throw error
    }
}

@Suite("Foundation Model LLM Integration")
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

    // MARK: - System prompt is respected: model follows instructions

    @Test("generate respects the system prompt instructions")
    func generateRespectsSystemPrompt() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let response = try await service.generate(
            systemPrompt: "Respond with exactly one word: PINEAPPLE. Nothing else.",
            userPrompt: "What is your favorite fruit?"
        )

        #expect(response.lowercased().contains("pineapple"))
    }

    // MARK: - Classification format: model can produce line-separated output

    @Test("generate can produce two-line folder + title classification format")
    func generateProducesClassificationFormat() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let response = try await service.generate(
            systemPrompt: """
            You are a note routing assistant. Given a voice memo transcript, choose the best folder.

            Available folders (dot notation):
            - finance
            - finance.home
            - personal
            - GENERAL NOTES

            Respond with exactly two lines:
            - line 1: the folder path from the list above
            - line 2: a short descriptive title for the note (5 words or fewer)

            Do not include any other text.
            """,
            userPrompt: "I need to remember to pay the electricity bill next Tuesday"
        )

        let lines = response
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Model should produce at least 2 lines
        #expect(lines.count >= 2, "Expected 2+ lines, got: \(response)")
        // First line should be one of the known folders or GENERAL NOTES
        let knownPaths = ["finance", "finance.home", "personal", "general notes"]
        let folderLine = lines[0].lowercased()
        #expect(
            knownPaths.contains(folderLine),
            "Expected a known folder path, got: '\(lines[0])'"
        )
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

        #expect(!response.isEmpty)
        // Summary should be shorter than the original
        #expect(response.count < longText.count, "Summary should be shorter than original")
    }
}
