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
        // Contains few-shot examples
        #expect(call.systemPrompt.contains("Transcript:"))
        #expect(call.systemPrompt.contains("Two lines only") || call.systemPrompt.contains("two lines"))
    }

    // MARK: - Label stripping

    @Test
    func folderPrefixStripped() async throws {
        let llm = MockLLMService()
        llm.result = "Folder: finance.home\nTitle: Budget Review"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: "finance.home", title: "Budget Review"))
    }

    @Test
    func pathPrefixStripped() async throws {
        let llm = MockLLMService()
        llm.result = "Path: personal\nTitle: Quick note"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: "personal", title: "Quick note"))
    }

    @Test
    func linePrefixStripped() async throws {
        let llm = MockLLMService()
        llm.result = "Line 1: GENERAL NOTES\nLine 2: Misc"
        let hierarchy = makeHierarchy(["finance", "finance.home", "personal"])
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 14, minute: 30)

        let result = try await TranscriptClassifier.classify(
            transcript: "Some thought",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        #expect(result == NoteClassificationResult(folderPath: nil, title: "Misc"))
    }

    // MARK: - Custom system prompt

    @Test
    func classifyWithCustomPromptReplacesNotesFolders() async throws {
        let llm = MockLLMService()
        llm.result = "Work\nProject update"
        let work = NotesFolder(id: "w", name: "Work")
        let personal = NotesFolder(id: "p", name: "Personal")
        let hierarchy = [
            FolderHierarchyEntry(path: "Work", folder: work),
            FolderHierarchyEntry(path: "Work.Meetings", folder: NotesFolder(id: "wm", name: "Meetings")),
            FolderHierarchyEntry(path: "Personal", folder: personal),
        ]
        let now = makeDate(year: 2026, month: 4, day: 1, hour: 10, minute: 0)

        let result = try await TranscriptClassifier.classify(
            transcript: "Project update call",
            hierarchy: hierarchy,
            using: llm,
            customSystemPrompt: "Route to:\n{notes_folders}",
            now: now
        )

        // The LLM should have received the custom prompt with {notes_folders} replaced
        // by ONLY top-level folder names (path without ".")
        let call = try #require(llm.calls.first)
        #expect(call.systemPrompt == "Route to:\n- Work\n- Personal")
        #expect(result.folderPath == "Work")
    }

    @Test
    func classifyWithCustomPromptWithoutPlaceholderPassesAsIs() async throws {
        let llm = MockLLMService()
        llm.result = "GENERAL NOTES\nNote title"
        let hierarchy = makeHierarchy(["finance", "personal"])
        let now = makeDate(year: 2026, month: 4, day: 1, hour: 10, minute: 0)

        _ = try await TranscriptClassifier.classify(
            transcript: "Something",
            hierarchy: hierarchy,
            using: llm,
            customSystemPrompt: "Just pick a folder",
            now: now
        )

        let call = try #require(llm.calls.first)
        #expect(call.systemPrompt == "Just pick a folder")
    }

    @Test
    func classifyWithoutCustomPromptUsesBuiltIn() async throws {
        let llm = MockLLMService()
        llm.result = "GENERAL NOTES\nTitle"
        let hierarchy = makeHierarchy(["finance", "personal"])
        let now = makeDate(year: 2026, month: 4, day: 1, hour: 10, minute: 0)

        _ = try await TranscriptClassifier.classify(
            transcript: "Something",
            hierarchy: hierarchy,
            using: llm,
            now: now
        )

        let call = try #require(llm.calls.first)
        // Built-in prompt contains hierarchy paths
        #expect(call.systemPrompt.contains("- finance"))
        #expect(call.systemPrompt.contains("- personal"))
        #expect(call.systemPrompt.contains("GENERAL NOTES"))
    }
}
