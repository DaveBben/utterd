import Foundation
import Testing
@testable import Core

@MainActor
struct MockLLMServiceTests {

    // MARK: - MockLLMService

    @Test func mockLLMServiceReturnsConfiguredResult() async throws {
        let mock = MockLLMService()
        mock.result = "hello"

        let output = try await mock.generate(systemPrompt: "sys", userPrompt: "usr")

        #expect(output == "hello")
    }

    @Test func mockLLMServiceRecordsCalls() async throws {
        let mock = MockLLMService()
        mock.result = "hello"

        _ = try await mock.generate(systemPrompt: "sys", userPrompt: "usr")

        #expect(mock.calls.count == 1)
        #expect(mock.calls[0].systemPrompt == "sys")
        #expect(mock.calls[0].userPrompt == "usr")
    }

    @Test func mockLLMServiceThrowsConfiguredError() async throws {
        let mock = MockLLMService()
        mock.error = CocoaError(.fileNoSuchFile)

        await #expect(throws: CocoaError.self) {
            _ = try await mock.generate(systemPrompt: "sys", userPrompt: "usr")
        }
    }

    // MARK: - MockTranscriptSummarizer

    @Test func mockTranscriptSummarizerReturnsConfiguredResult() async throws {
        let mock = MockTranscriptSummarizer()
        mock.result = "summary"
        let budget = LLMContextBudget(totalWords: 3000, systemPromptOverhead: 200)

        let output = try await mock.summarize(transcript: "long text", contextBudget: budget)

        #expect(output == "summary")
    }

    @Test func mockTranscriptSummarizerRecordsCalls() async throws {
        let mock = MockTranscriptSummarizer()
        mock.result = "summary"
        let budget = LLMContextBudget(totalWords: 3000, systemPromptOverhead: 200)

        _ = try await mock.summarize(transcript: "long text", contextBudget: budget)

        #expect(mock.calls.count == 1)
        #expect(mock.calls[0].transcript == "long text")
        #expect(mock.calls[0].contextBudget == budget)
    }

    @Test func mockTranscriptSummarizerThrowsConfiguredError() async throws {
        let mock = MockTranscriptSummarizer()
        mock.error = CocoaError(.fileNoSuchFile)
        let budget = LLMContextBudget(totalWords: 3000, systemPromptOverhead: 200)

        await #expect(throws: CocoaError.self) {
            _ = try await mock.summarize(transcript: "long text", contextBudget: budget)
        }
    }
}
