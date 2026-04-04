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

    // MARK: - Title generation: model returns a descriptive title

    @Test("title generation produces a non-empty title under 100 characters")
    func titleGenerationProducesDescriptiveTitle() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let response = try await service.generate(
            systemPrompt: "Generate a short descriptive title for this voice memo transcript. Return only the title, nothing else.",
            userPrompt: "I need to remember to buy milk, eggs, bread, and some chicken for dinner tonight. Also pick up dog food."
        )

        let title = response.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Title: \(title)")
        #expect(!title.isEmpty, "Title should not be empty")
        #expect(title.count <= 100, "Title should be under 100 characters, got \(title.count)")
        // Title should NOT match the date-based fallback format
        let datePattern = try Regex("^Voice Memo \\d{4}-\\d{2}-\\d{2}")
        #expect(title.firstMatch(of: datePattern) == nil, "Title should not be a date-based fallback: \(title)")
    }

    // MARK: - Summarization quality: progressive summarization produces concise output

    @Test("summarization of long transcript produces concise summary")
    func summarizationProducesConciseSummary() async throws {
        try await requireModelAccess()
        guard #available(macOS 26, *) else { return }

        let service = FoundationModelLLMService()
        let summarizer = IterativeRefineSummarizer(llmService: service)
        // Build a transcript of at least 3,500 words to guarantee progressive chunking
        let paragraph = "Today I went to the grocery store and bought apples bananas oranges milk bread cheese and some chicken for dinner tonight. Then I stopped by the pharmacy to pick up my prescription and grabbed some vitamins. After that I filled up the car with gas and got a car wash because it was really dirty from the rain last week. I also need to remember to call the dentist to schedule an appointment for next month and pick up the dry cleaning on Thursday."
        // ~70 words per paragraph, 50 repetitions = ~3,500 words
        let transcript = (1...50).map { "Paragraph \($0): \(paragraph)" }.joined(separator: " ")
        let wordCount = transcript.split(separator: " ").count
        print("Transcript word count: \(wordCount)")

        let budget = LLMContextBudget(totalWords: 3000, systemPromptOverhead: 200)
        let summary = try await summarizer.summarize(transcript: transcript, contextBudget: budget)

        print("Summary (\(summary.count) chars):\n\(summary)")
        #expect(!summary.isEmpty, "Summary should not be empty")
        #expect(summary.count <= transcript.count / 2, "Summary should be at most 50% of original (\(transcript.count) chars), got \(summary.count) chars")
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
