/// Abstracts transcript summarization so tests can inject a mock.
///
/// Concrete implementations receive the `LLMService` at init time,
/// keeping the call site free of LLM details.
public protocol TranscriptSummarizer: Sendable {
    func summarize(transcript: String, contextBudget: LLMContextBudget) async throws -> String
}
