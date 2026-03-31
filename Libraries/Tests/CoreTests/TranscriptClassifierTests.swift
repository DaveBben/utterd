import Testing
import Foundation
@testable import Core

@MainActor
struct TranscriptClassifierTests {

    // MARK: - Helpers

    private func makeHierarchy(_ paths: [String]) -> [FolderHierarchyEntry] {
        paths.map { FolderHierarchyEntry(path: $0, folder: NotesFolder(id: $0, name: $0)) }
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Happy path

    @Test
    func classifiesKnownFolderWithTitle() async throws {
        let llm = MockLLMService()
        llm.result = "finance.home\nGrocery list for March"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Buy milk",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: "finance.home", title: "Grocery list for March"))
    }

    // MARK: - GENERAL NOTES fallback

    @Test
    func generalNotesResponseProducesNilFolderPath() async throws {
        let llm = MockLLMService()
        llm.result = "GENERAL NOTES\nRandom thoughts"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Random thoughts",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: nil, title: "Random thoughts"))
    }

    // MARK: - Unrecognized folder

    @Test
    func unrecognizedFolderTreatedAsGeneral() async throws {
        let llm = MockLLMService()
        llm.result = "nonexistent.folder\nSome title"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: nil, title: "Some title"))
    }

    // MARK: - Case-insensitive + whitespace trimming

    @Test
    func caseInsensitiveAndWhitespaceTrimmedMatching() async throws {
        let llm = MockLLMService()
        llm.result = " Finance.Home \n  Title  "
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: "finance.home", title: "Title"))
    }

    // MARK: - Missing title (single line, date-based fallback)

    @Test
    func missingTitleProducesDateBasedFallback() async throws {
        let llm = MockLLMService()
        llm.result = "finance.home"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: "finance.home", title: "Voice Memo 2026-03-31 14:30"))
    }

    // MARK: - Empty response

    @Test
    func emptyResponseProducesNilFolderAndDateFallback() async throws {
        let llm = MockLLMService()
        llm.result = ""
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: nil, title: "Voice Memo 2026-03-31 14:30"))
    }

    // MARK: - System prompt contents

    @Test
    func systemPromptContainsHierarchyAndInstructions() async throws {
        let llm = MockLLMService()
        llm.result = "GENERAL NOTES\nTitle"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        _ = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        let call = try #require(llm.calls.first)
        #expect(call.systemPrompt.contains("finance"))
        #expect(call.systemPrompt.contains("finance.home"))
        #expect(call.systemPrompt.contains("personal"))
        #expect(call.systemPrompt.contains("GENERAL NOTES"))
        // Instructs line-separated format
        #expect(call.systemPrompt.contains("line 1") || call.systemPrompt.contains("first line"))
        #expect(call.systemPrompt.contains("line 2") || call.systemPrompt.contains("second line"))
    }
}
