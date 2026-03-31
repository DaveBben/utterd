/// Budget parameters for fitting content within the LLM's context window.
///
/// `totalWords` is a conservative proxy for the token limit (~3K words ≈ ~4K tokens).
/// Chunk sizing subtracts system prompt overhead dynamically rather than using a hardcoded number.
///
/// Valid ranges:
/// - `totalWords` must exceed `systemPromptOverhead` — otherwise `availableForContent` is zero or negative.
/// - `summaryReserveRatio` must be in `[0, 1)` — a ratio of 1.0 would leave zero words for new chunks,
///   causing a zero step size in the iterative refinement loop.
public struct LLMContextBudget: Sendable, Equatable {
    public let totalWords: Int
    public let systemPromptOverhead: Int
    public let summaryReserveRatio: Double

    /// Words available for content after subtracting the system prompt overhead.
    public var availableForContent: Int {
        totalWords - systemPromptOverhead
    }

    /// Words available for a new chunk, reserving space for the rolling summary.
    public var availableForNewChunk: Int {
        Int(Double(availableForContent) * (1 - summaryReserveRatio))
    }

    public init(totalWords: Int, systemPromptOverhead: Int, summaryReserveRatio: Double = 0.3) {
        precondition(totalWords > systemPromptOverhead, "totalWords must exceed systemPromptOverhead")
        precondition(summaryReserveRatio >= 0 && summaryReserveRatio < 1, "summaryReserveRatio must be in [0, 1)")
        self.totalWords = totalWords
        self.systemPromptOverhead = systemPromptOverhead
        self.summaryReserveRatio = summaryReserveRatio
    }
}
