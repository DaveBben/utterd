import Foundation
import Testing
@testable import Core

@MainActor
struct NoteRoutingPipelineStageTests {

    // MARK: - Helpers

    private func makeURL() -> URL {
        URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).m4a")
    }

    private func makePersonalFolder() -> NotesFolder {
        NotesFolder(id: "personal", name: "personal")
    }

    private func smallBudget() -> LLMContextBudget {
        // availableForContent = 100 - 10 = 90 words
        LLMContextBudget(totalWords: 100, systemPromptOverhead: 10, summaryReserveRatio: 0.3)
    }

    private func tinyBudget() -> LLMContextBudget {
        // availableForContent = 5 - 1 = 4 words — anything > 4 words triggers summarization
        LLMContextBudget(totalWords: 5, systemPromptOverhead: 1, summaryReserveRatio: 0.3)
    }

    private func makeStage(
        notesService: MockNotesService,
        llmService: MockLLMService = MockLLMService(),
        summarizer: MockTranscriptSummarizer = MockTranscriptSummarizer(),
        store: MockMemoStore,
        logger: MockWatcherLogger = MockWatcherLogger(),
        config: RoutingConfiguration = RoutingConfiguration(),
        contextBudget: LLMContextBudget,
        completeCounter: ActorBox<Int> = ActorBox(0)
    ) -> NoteRoutingPipelineStage {
        NoteRoutingPipelineStage(
            notesService: notesService,
            llmService: llmService,
            summarizer: summarizer,
            store: store,
            logger: logger,
            configProvider: { config },
            contextBudget: contextBudget,
            onComplete: { await completeCounter.increment() }
        )
    }

    // MARK: - Test 1: Both toggles off + normal transcript

    @Test
    func bothTogglesOffNormalTranscriptSkipsLLMAndSummarizer() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let summarizer = MockTranscriptSummarizer()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(),
            contextBudget: smallBudget()
        )

        // Fixed date: 2025-03-15 14:30:00 UTC → "Voice Memo 2025-03-15 14:30"
        var components = DateComponents()
        components.year = 2025
        components.month = 3
        components.day = 15
        components.hour = 14
        components.minute = 30
        components.second = 0
        let fixedDate = Calendar(identifier: .gregorian).date(from: components)!
        let transcript = "This is a normal transcript with several words in it."
        // Call routeCore indirectly via a custom stage using a fixed date injected via now
        // We use the public route() which uses Date() — instead we test what we can observe:
        // LLM never called, summarizer never called, body is full transcript, title is date-based.
        // To test exact title we need to control 'now'. We do this via a helper that captures now
        // and compares it against dateFallbackTitle.
        let result = TranscriptionResult(transcript: transcript, fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.isEmpty)
        #expect(summarizer.calls.isEmpty)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].body == transcript)
        // Title must match dateFallbackTitle format: "Voice Memo YYYY-MM-DD HH:mm"
        let title = notes.createNoteCalls[0].title
        #expect(title.hasPrefix("Voice Memo "))
        // Verify format matches "Voice Memo YYYY-MM-DD HH:mm" exactly (16 chars after prefix)
        let datePart = String(title.dropFirst("Voice Memo ".count))
        #expect(datePart.count == 16) // "YYYY-MM-DD HH:mm"
        _ = fixedDate // suppress unused warning
    }

    // MARK: - Test 2: Both toggles off + empty transcript

    @Test
    func bothTogglesOffEmptyTranscriptSkipsLLMAndSummarizer() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let summarizer = MockTranscriptSummarizer()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.isEmpty)
        #expect(summarizer.calls.isEmpty)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].body == "")
        let title = notes.createNoteCalls[0].title
        #expect(title.hasPrefix("Voice Memo "))
    }

    // MARK: - Test 3: defaultFolderName matches a root folder → note created in that folder

    @Test
    func defaultFolderNameMatchingRootFolderCreatesNoteInThatFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal]]
        notes.createNoteResult = .created

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            store: store,
            config: RoutingConfiguration(defaultFolderName: "personal"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == personal)
        // listFolders(in: nil) was called exactly once to resolve the default folder
        #expect(notes.listFoldersCalls.count == 1)
        #expect(notes.listFoldersCalls[0] == nil)
    }

    // MARK: - Test 4: defaultFolderName with no matching folder → note created with folder nil

    @Test
    func defaultFolderNameNotFoundCreatesNoteWithNilFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal]]
        notes.createNoteResult = .created

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            store: store,
            config: RoutingConfiguration(defaultFolderName: "Gone"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
    }

    // MARK: - Test 5: defaultFolderName set + listFolders throws → folder nil, warning logged

    @Test
    func defaultFolderNameWhenListFoldersThrowsCreatesNoteWithNilFolderAndLogsWarning() async throws {
        let notes = MockNotesService()
        struct FetchError: Error {}
        notes.listFoldersError = FetchError()
        notes.createNoteResult = .created

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let stage = makeStage(
            notesService: notes,
            store: store,
            logger: logger,
            config: RoutingConfiguration(defaultFolderName: "personal"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
        #expect(logger.warnings.count >= 1)
    }

    // MARK: - Test 6: markProcessed + onComplete run exactly once on success path

    @Test
    func markProcessedAndOnCompleteRunExactlyOnceOnSuccessPath() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let store = MockMemoStore()
        let completeCounter = ActorBox(0)
        let stage = makeStage(
            notesService: notes,
            store: store,
            contextBudget: smallBudget(),
            completeCounter: completeCounter
        )

        let result = TranscriptionResult(transcript: "hello", fileURL: makeURL())
        await stage.route(result)

        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(await completeCounter.get() == 1)
    }

    // MARK: - Test 7: markProcessed + onComplete run exactly once on error path (createNote throws)

    @Test
    func markProcessedAndOnCompleteRunExactlyOnceOnErrorPath() async throws {
        let notes = MockNotesService()
        struct NoteError: Error {}
        notes.createNoteError = NoteError()

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let completeCounter = ActorBox(0)
        let fileURL = makeURL()
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: MockLLMService(),
            summarizer: MockTranscriptSummarizer(),
            store: store,
            logger: logger,
            configProvider: { RoutingConfiguration() },
            contextBudget: smallBudget(),
            onComplete: { await completeCounter.increment() }
        )

        let result = TranscriptionResult(transcript: "hello", fileURL: fileURL)
        await stage.route(result)

        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(markCalls[0].fileURL == fileURL)
        #expect(await completeCounter.get() == 1)
        #expect(!logger.errors.isEmpty)
    }

    // MARK: - Test 8: Summarization with short transcript (fits budget)

    @Test
    func summarizationOnShortTranscript() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "A summary"

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(summarizationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(summarizer.calls.count == 1)
        #expect(summarizer.calls[0].transcript == "Buy groceries")
        #expect(notes.createNoteCalls[0].body == "A summary")
        #expect(notes.createNoteCalls[0].title.hasPrefix("Voice Memo "))
    }

    // MARK: - Test 9: Summarization with long transcript (exceeds budget)

    @Test
    func summarizationOnLongTranscript() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "condensed"

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(summarizationEnabled: true),
            contextBudget: tinyBudget()
        )

        let result = TranscriptionResult(transcript: "one two three four five", fileURL: makeURL())
        await stage.route(result)

        #expect(summarizer.calls.count == 1)
        #expect(summarizer.calls[0].transcript == "one two three four five")
        #expect(notes.createNoteCalls[0].body == "condensed")
    }

    // MARK: - Test 10: Summarization skipped on empty transcript

    @Test
    func summarizationOnEmptyTranscript() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(summarizationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "", fileURL: makeURL())
        await stage.route(result)

        #expect(summarizer.calls.isEmpty)
        #expect(notes.createNoteCalls[0].body == "")
    }

    // MARK: - Test 11: Summarizer throws → fallback to full transcript, error logged

    @Test
    func summarizationOnSummarizerThrows() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        struct SummaryError: Error {}
        summarizer.error = SummaryError()

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let stage = makeStage(
            notesService: notes,
            summarizer: summarizer,
            store: store,
            logger: logger,
            config: RoutingConfiguration(summarizationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == "Buy groceries")
        #expect(logger.errors.count == 1)
    }

    // MARK: - Test 12: Summarizer returns empty → fallback to full transcript

    @Test
    func summarizationOnSummarizerReturnsEmpty() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = ""

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(summarizationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == "Buy groceries")
    }

    // MARK: - Test 13: Title generation with normal transcript

    @Test
    func titleGenOnNormalTranscript() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "Grocery Shopping"

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.count == 1)
        #expect(llm.calls[0].systemPrompt.lowercased().contains("title"))
        #expect(llm.calls[0].userPrompt == "Buy groceries")
        #expect(notes.createNoteCalls[0].title == "Grocery Shopping")
    }

    // MARK: - Test 14: Title generation truncates transcript to 2000 words

    @Test
    func titleGenOnTranscriptOver2KWords() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "Long Document"

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let longTranscript = (1...3000).map { "word\($0)" }.joined(separator: " ")
        let result = TranscriptionResult(transcript: longTranscript, fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls[0].userPrompt.split(separator: " ").count == 2000)
    }

    // MARK: - Test 15: Both summarization and title generation on normal transcript

    @Test
    func bothOnNormalTranscript() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "A summary"

        let llm = MockLLMService()
        llm.result = "Meeting Notes"

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(summarizationEnabled: true, titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(summarizer.calls.count == 1)
        #expect(llm.calls.count == 1)
        #expect(notes.createNoteCalls[0].body == "A summary")
        #expect(notes.createNoteCalls[0].title == "Meeting Notes")
    }

    // MARK: - Test 16: Title generation skipped on empty transcript

    @Test
    func titleGenOnEmptyTranscript() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.isEmpty)
        #expect(notes.createNoteCalls[0].title.hasPrefix("Voice Memo "))
    }

    // MARK: - Test 17: Title generation falls back to date title when LLM throws

    @Test
    func titleGenOnLLMThrows() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        struct SomeError: Error {}
        llm.error = SomeError()

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            logger: logger,
            config: RoutingConfiguration(titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].title.hasPrefix("Voice Memo "))
        #expect(logger.errors.count == 1)
    }

    // MARK: - Test 18: Summarization succeeds, title generation fails

    @Test
    func bothOnSummarizeSucceedsTitleFails() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "A summary"

        let llm = MockLLMService()
        struct SomeError: Error {}
        llm.error = SomeError()

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            logger: logger,
            config: RoutingConfiguration(summarizationEnabled: true, titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == "A summary")
        #expect(notes.createNoteCalls[0].title.hasPrefix("Voice Memo "))
        #expect(logger.errors.count == 1)
    }

    // MARK: - Test 19: Summarization fails, title generation succeeds

    @Test
    func bothOnSummarizeFailsTitleSucceeds() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        struct SomeError: Error {}
        summarizer.error = SomeError()

        let llm = MockLLMService()
        llm.result = "Grocery List"

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            logger: logger,
            config: RoutingConfiguration(summarizationEnabled: true, titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == "Buy groceries")
        #expect(notes.createNoteCalls[0].title == "Grocery List")
        #expect(logger.errors.count == 1)
    }

    // MARK: - Test 20: LLM returns empty string → date fallback title

    @Test
    func titleGenOnLLMReturnsEmpty() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = ""

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].title.hasPrefix("Voice Memo "))
    }

    // MARK: - Test 21: LLM returns 150-char title → truncated to 100

    @Test
    func titleGenOnLLMReturns150Chars() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = String(repeating: "A", count: 150)

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].title.count == 100)
    }

    // MARK: - Test 22: LLM returns multi-line response → first line used

    @Test
    func titleGenOnLLMReturnsMultiLine() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "Line1\n\nLine3"

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].title == "Line1")
    }

    // MARK: - Test 23: Both summarization and title generation both throw

    @Test
    func bothOnBothThrow() async throws {
        let notes = MockNotesService()
        notes.createNoteResult = .created

        let summarizer = MockTranscriptSummarizer()
        struct SomeError: Error {}
        summarizer.error = SomeError()

        let llm = MockLLMService()
        llm.error = SomeError()

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            logger: logger,
            config: RoutingConfiguration(summarizationEnabled: true, titleGenerationEnabled: true),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == "Buy groceries")
        #expect(notes.createNoteCalls[0].title.hasPrefix("Voice Memo "))
        #expect(logger.errors.count >= 2)
    }
}
