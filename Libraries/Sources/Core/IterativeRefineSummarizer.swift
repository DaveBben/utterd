/// Summarizes a transcript by splitting it into word-count-bounded chunks and
/// iteratively refining a rolling summary with each chunk.
///
/// When the transcript fits in one chunk (word count ≤ `contextBudget.availableForNewChunk`),
/// the LLM is called once with a "summarize" instruction. For subsequent chunks,
/// the rolling summary from the previous call is prepended so the LLM can refine it.
public struct IterativeRefineSummarizer: TranscriptSummarizer {
    private let llmService: any LLMService

    public init(llmService: any LLMService) {
        self.llmService = llmService
    }

    public func summarize(transcript: String, contextBudget: LLMContextBudget) async throws -> String {
        let words = transcript.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let chunkSize = contextBudget.availableForNewChunk
        let chunks = stride(from: 0, to: words.count, by: chunkSize).map { start in
            words[start..<min(start + chunkSize, words.count)].joined(separator: " ")
        }

        // Reserve words for the prompt template text ("Update this summary…\n")
        let promptOverhead = 8
        let summaryBudget = max(1, contextBudget.availableForContent - chunkSize - promptOverhead)
        var rollingSummary = ""
        for (index, chunk) in chunks.enumerated() {
            let userPrompt: String
            if index == 0 {
                userPrompt = "Summarize this transcript segment:\n\(chunk)"
            } else {
                let truncatedSummary = rollingSummary
                    .split(separator: " ")
                    .prefix(summaryBudget)
                    .joined(separator: " ")
                userPrompt = "Update this summary with the new content:\n\(truncatedSummary)\n\(chunk)"
            }
            let systemPrompt = "You are a concise summarizer. Return only the summary text."
            rollingSummary = try await llmService.generate(systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
        return rollingSummary
    }
}
