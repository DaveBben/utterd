import Testing
import Foundation
@testable import Core

// A mock that returns responses from a pre-set sequence, optionally throwing on a specific call index.
private final class SequenceMockLLMService: LLMService, @unchecked Sendable {
    nonisolated(unsafe) var responses: [String]
    nonisolated(unsafe) var errorOnCallIndex: Int?
    nonisolated(unsafe) private(set) var calls: [(systemPrompt: String, userPrompt: String)] = []

    init(responses: [String], errorOnCallIndex: Int? = nil) {
        self.responses = responses
        self.errorOnCallIndex = errorOnCallIndex
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        let index = calls.count
        calls.append((systemPrompt: systemPrompt, userPrompt: userPrompt))
        if let errorIndex = errorOnCallIndex, index == errorIndex {
            throw URLError(.badServerResponse)
        }
        return responses[index]
    }
}

@MainActor
struct IterativeRefineSummarizerTests {

    // Budget: totalWords=2000, systemOverhead=200, reserveRatio=0.3
    // availableForContent = 1800
    // availableForNewChunk = Int(1800 * 0.7) = 1260
    private func makeBudget(totalWords: Int = 2000, systemOverhead: Int = 200, reserveRatio: Double = 0.3) -> LLMContextBudget {
        LLMContextBudget(totalWords: totalWords, systemPromptOverhead: systemOverhead, summaryReserveRatio: reserveRatio)
    }

    private func makeWords(_ count: Int) -> String {
        (1...count).map { "word\($0)" }.joined(separator: " ")
    }

    // MARK: - Single chunk

    @Test
    func singleChunkTranscriptCallsLLMOnce() async throws {
        // Budget with availableForNewChunk = 1000
        // totalWords=1300, overhead=100, reserve=0.3 -> availableForContent=1200 -> availableForNewChunk=840
        // Use: total=2100, overhead=100, reserve=0.3 -> content=2000 -> chunk=1400 -> 500 words fits
        let budget = LLMContextBudget(totalWords: 1600, systemPromptOverhead: 100, summaryReserveRatio: 0.3)
        // availableForContent = 1500, availableForNewChunk = Int(1500 * 0.7) = 1050
        let transcript = makeWords(500)
        let llm = SequenceMockLLMService(responses: ["Summary of 500 words"])

        let summarizer = IterativeRefineSummarizer(llmService: llm)
        let result = try await summarizer.summarize(transcript: transcript, contextBudget: budget)

        #expect(llm.calls.count == 1)
        #expect(result == "Summary of 500 words")
    }

    // MARK: - Two chunks

    @Test
    func twoChunkTranscriptCallsLLMTwice() async throws {
        // availableForNewChunk = 560 means transcript of ~1000 words → 2 chunks (560 + 440)
        // total=1000, overhead=200, reserve=0.3 -> content=800 -> chunk=Int(800*0.7)=560
        let budget = LLMContextBudget(totalWords: 1000, systemPromptOverhead: 200, summaryReserveRatio: 0.3)
        let transcript = makeWords(1000)
        let llm = SequenceMockLLMService(responses: ["summary after chunk 1", "summary after chunk 2"])

        let summarizer = IterativeRefineSummarizer(llmService: llm)
        let result = try await summarizer.summarize(transcript: transcript, contextBudget: budget)

        #expect(llm.calls.count == 2)
        #expect(result == "summary after chunk 2")
    }

    // MARK: - Rolling summary included in subsequent calls

    @Test
    func subsequentCallsIncludeRollingSummary() async throws {
        // total=1000, overhead=200, reserve=0.3 -> content=800 -> chunk=560
        let budget = LLMContextBudget(totalWords: 1000, systemPromptOverhead: 200, summaryReserveRatio: 0.3)
        let transcript = makeWords(1200)
        // 1200 words / 560 per chunk = ceil(2.14) = 3 chunks
        let llm = SequenceMockLLMService(responses: ["summary1", "summary2", "summary3"])

        let summarizer = IterativeRefineSummarizer(llmService: llm)
        let result = try await summarizer.summarize(transcript: transcript, contextBudget: budget)

        #expect(llm.calls.count == 3)
        // Second call's user prompt must contain the first summary
        let secondPrompt = llm.calls[1].userPrompt
        #expect(secondPrompt.contains("summary1"))
        // Third call's user prompt must contain the second summary
        let thirdPrompt = llm.calls[2].userPrompt
        #expect(thirdPrompt.contains("summary2"))
        #expect(result == "summary3")
    }

    // MARK: - 4 calls for 2000-word transcript with chunk size 560

    @Test
    func fourChunksFor2000WordTranscript() async throws {
        // total=1000, overhead=200, reserve=0.3 -> content=800 -> chunk=560
        // 2000/560 = 3.57 -> 4 chunks
        let budget = LLMContextBudget(totalWords: 1000, systemPromptOverhead: 200, summaryReserveRatio: 0.3)
        let transcript = makeWords(2000)
        let llm = SequenceMockLLMService(responses: ["s1", "s2", "s3", "s4"])

        let summarizer = IterativeRefineSummarizer(llmService: llm)
        let result = try await summarizer.summarize(transcript: transcript, contextBudget: budget)

        #expect(llm.calls.count == 4)
        #expect(result == "s4")
    }

    // MARK: - User prompt word count invariant

    @Test
    func userPromptWordCountDoesNotExceedAvailableForContent() async throws {
        // total=1000, overhead=200, reserve=0.3 -> content=800 -> chunk=560
        let budget = LLMContextBudget(totalWords: 1000, systemPromptOverhead: 200, summaryReserveRatio: 0.3)
        let transcript = makeWords(2000)
        let llm = SequenceMockLLMService(responses: ["s1", "s2", "s3", "s4"])

        let summarizer = IterativeRefineSummarizer(llmService: llm)
        _ = try await summarizer.summarize(transcript: transcript, contextBudget: budget)

        let availableForContent = budget.availableForContent
        for call in llm.calls {
            let wordCount = call.userPrompt.split(separator: " ").count
            #expect(wordCount <= availableForContent, "User prompt had \(wordCount) words, limit is \(availableForContent)")
        }
    }

    // MARK: - Word boundary splitting

    @Test
    func chunksSplitAtWordBoundaries() async throws {
        // total=1000, overhead=200, reserve=0.3 -> content=800 -> chunk=560
        let budget = LLMContextBudget(totalWords: 1000, systemPromptOverhead: 200, summaryReserveRatio: 0.3)
        let transcript = makeWords(1200)
        let llm = SequenceMockLLMService(responses: ["s1", "s2", "s3"])

        let summarizer = IterativeRefineSummarizer(llmService: llm)
        _ = try await summarizer.summarize(transcript: transcript, contextBudget: budget)

        // Every word in every call's content must be a complete word from the original transcript
        let allWords = Set(transcript.split(separator: " ").map(String.init))
        for call in llm.calls {
            // Extract words from the user prompt — all must be known words (no partial splits)
            let promptWords = call.userPrompt.split(separator: " ").map(String.init)
            for word in promptWords {
                // Allow summary words (they come from LLM responses like "s1", "s2") or transcript words
                let knownSummaries = Set(["s1", "s2", "s3", "summary", "this", "transcript", "segment",
                                          "update", "with", "the", "new", "content", "previous", "summary:"])
                if !knownSummaries.contains(word) && !allWords.contains(word) {
                    // Any word not from the transcript or known instruction words is suspicious
                    // but we only care that it's not a half-word from the transcript
                    let isPartialWord = allWords.contains { original in
                        original.hasPrefix(word) && original != word
                    }
                    #expect(!isPartialWord, "Found partial word '\(word)' in prompt — splitting mid-word")
                }
            }
        }
    }

    // MARK: - Error propagation

    @Test
    func errorOnSecondCallPropagates() async throws {
        // total=1000, overhead=200, reserve=0.3 -> content=800 -> chunk=560
        let budget = LLMContextBudget(totalWords: 1000, systemPromptOverhead: 200, summaryReserveRatio: 0.3)
        let transcript = makeWords(1200) // 3 chunks
        let llm = SequenceMockLLMService(responses: ["s1", "s2", "s3"], errorOnCallIndex: 1)

        let summarizer = IterativeRefineSummarizer(llmService: llm)

        await #expect(throws: URLError.self) {
            _ = try await summarizer.summarize(transcript: transcript, contextBudget: budget)
        }
        // Should have made exactly 2 calls (first succeeds, second throws)
        #expect(llm.calls.count == 2)
    }
}
