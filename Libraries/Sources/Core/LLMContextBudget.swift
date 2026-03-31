/// Budget parameters for fitting content within the LLM's context window.
///
/// `totalWords` is a conservative proxy for the token limit (~3K words ≈ ~4K tokens).
/// Chunk sizing subtracts system prompt overhead dynamically rather than using a hardcoded number.
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
        self.totalWords = totalWords
        self.systemPromptOverhead = systemPromptOverhead
        self.summaryReserveRatio = summaryReserveRatio
    }
}
