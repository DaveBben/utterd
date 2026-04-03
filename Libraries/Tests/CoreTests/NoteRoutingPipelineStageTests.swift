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
        llmService: MockLLMService,
        summarizer: MockTranscriptSummarizer = MockTranscriptSummarizer(),
        store: MockMemoStore,
        logger: MockWatcherLogger = MockWatcherLogger(),
        config: RoutingConfiguration = RoutingConfiguration(llmApproach: .autoRoute),
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

    // MARK: - Short transcript: happy path

    @Test
    func shortTranscriptClassifiesAndCreatesNoteInMatchedFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nGrocery list"

        let store = MockMemoStore()
        let completeCounter = ActorBox(0)
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            contextBudget: smallBudget(),
            completeCounter: completeCounter
        )

        let result = TranscriptionResult(
            transcript: "Buy groceries",
            fileURL: makeURL()
        )
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].title == "Grocery list")
        #expect(notes.createNoteCalls[0].body == "Buy groceries")
        #expect(notes.createNoteCalls[0].folder == personal)
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(await completeCounter.get() == 1)
    }

    // MARK: - Long transcript: summarizer used for classification but full transcript as body

    @Test
    func longTranscriptSummarizedForClassificationButFullTranscriptUsedAsBody() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nMeeting notes"

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "condensed text"

        let store = MockMemoStore()
        // tinyBudget: 4 word limit — "one two three four five" is 5 words, exceeds budget
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute) },
            contextBudget: tinyBudget(),
            onComplete: {}
        )

        let fullTranscript = "one two three four five"
        let result = TranscriptionResult(transcript: fullTranscript, fileURL: makeURL())
        await stage.route(result)

        // Summarizer was called
        #expect(summarizer.calls.count == 1)
        // LLM received the condensed text, not the full transcript
        #expect(llm.calls.count == 1)
        #expect(llm.calls[0].userPrompt == "condensed text")
        // Note body is the full original transcript (routeOnly)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].body == fullTranscript)
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
    }

    // MARK: - Empty transcript: skip classification, create in default folder

    @Test
    func emptyTranscriptSkipsClassificationAndCreatesInDefaultFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let summarizer = MockTranscriptSummarizer()
        let store = MockMemoStore()
        let completeCounter = ActorBox(0)
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            contextBudget: smallBudget(),
            completeCounter: completeCounter
        )

        let result = TranscriptionResult(transcript: "", fileURL: makeURL())
        await stage.route(result)

        #expect(summarizer.calls.isEmpty)
        #expect(llm.calls.isEmpty)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
        #expect(notes.createNoteCalls[0].body == "")
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(await completeCounter.get() == 1)
    }

    // MARK: - Unrecognized folder from classifier: default folder

    @Test
    func unrecognizedFolderFromClassifierCreatesNoteInDefaultFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "unknown.path\nSome title"  // not in hierarchy

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
    }

    // MARK: - Empty folder hierarchy: skip classification, create in default folder

    @Test
    func emptyFolderHierarchySkipsClassificationAndCreatesInDefaultFolder() async throws {
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: []]  // empty root

        let llm = MockLLMService()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.isEmpty)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
    }

    // MARK: - LLM error: logs, marks processed, fires onComplete, does not throw

    @Test
    func llmErrorLogsAndMarksProcessedAndFiresOnComplete() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]

        struct LLMError: Error {}
        let llm = MockLLMService()
        llm.error = LLMError()

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let completeCounter = ActorBox(0)
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: MockTranscriptSummarizer(),
            store: store,
            logger: logger,
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute) },
            contextBudget: smallBudget(),
            onComplete: { await completeCounter.increment() }
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)  // must not throw

        #expect(!logger.errors.isEmpty)
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(await completeCounter.get() == 1)
    }

    // MARK: - Note creation error: logs, marks processed, fires onComplete, does not throw

    @Test
    func noteCreationErrorLogsAndMarksProcessedAndFiresOnComplete() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]

        struct NoteError: Error {}
        notes.createNoteError = NoteError()

        let llm = MockLLMService()
        llm.result = "personal\nGrocery list"

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let completeCounter = ActorBox(0)
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: MockTranscriptSummarizer(),
            store: store,
            logger: logger,
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute) },
            contextBudget: smallBudget(),
            onComplete: { await completeCounter.increment() }
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)  // must not throw

        #expect(!logger.errors.isEmpty)
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(await completeCounter.get() == 1)
    }

    // MARK: - routeOnly mode: note body is always full transcript even after summarization

    @Test
    func routeOnlyModeUsesFullTranscriptAsBodyEvenAfterSummarization() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nMeeting notes"

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "summary text"

        let store = MockMemoStore()
        let fullTranscript = "one two three four five"
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute) },
            contextBudget: tinyBudget(),
            onComplete: {}
        )

        let result = TranscriptionResult(transcript: fullTranscript, fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == fullTranscript)
    }

    // MARK: - routeAndSummarize mode: note body is summary after summarization

    @Test
    func routeAndSummarizeModeUsesSummaryAsBodyAfterSummarization() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nMeeting notes"

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "summary text"

        let store = MockMemoStore()
        let fullTranscript = "one two three four five"
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute, summarizationEnabled: true) },
            contextBudget: tinyBudget(),
            onComplete: {}
        )

        let result = TranscriptionResult(transcript: fullTranscript, fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == "summary text")
    }

    // MARK: - routeAndSummarize mode with short transcript: no summarization, full transcript as body

    @Test
    func routeAndSummarizeModeDoesNotSummarizeShortTranscript() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nGrocery list"

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "summary"

        let store = MockMemoStore()
        // smallBudget: 90 word limit — "Buy groceries" is 2 words, well under limit
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute, summarizationEnabled: true) },
            contextBudget: smallBudget(),
            onComplete: {}
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(summarizer.calls.isEmpty)
        #expect(notes.createNoteCalls[0].body == "Buy groceries")
    }

    // MARK: - Both modes produce identical classification prompts

    @Test
    func bothModesProduceIdenticalClassificationSystemPrompts() async throws {
        let personal = makePersonalFolder()

        func makeNotes() -> MockNotesService {
            let notes = MockNotesService()
            notes.listFoldersByParent = [nil: [personal], "personal": []]
            notes.createNoteResult = .created
            return notes
        }

        let llmRouteOnly = MockLLMService()
        llmRouteOnly.result = "personal\nGrocery list"

        let llmRouteAndSummarize = MockLLMService()
        llmRouteAndSummarize.result = "personal\nGrocery list"

        let storeA = MockMemoStore()
        let storeB = MockMemoStore()
        let transcript = "Buy groceries"

        let stageRouteOnly = NoteRoutingPipelineStage(
            notesService: makeNotes(),
            llmService: llmRouteOnly,
            summarizer: MockTranscriptSummarizer(),
            store: storeA,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute) },
            contextBudget: smallBudget(),
            onComplete: {}
        )
        let stageRouteAndSummarize = NoteRoutingPipelineStage(
            notesService: makeNotes(),
            llmService: llmRouteAndSummarize,
            summarizer: MockTranscriptSummarizer(),
            store: storeB,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute, summarizationEnabled: true) },
            contextBudget: smallBudget(),
            onComplete: {}
        )

        let result = TranscriptionResult(transcript: transcript, fileURL: makeURL())
        await stageRouteOnly.route(result)
        await stageRouteAndSummarize.route(result)

        #expect(llmRouteOnly.calls.count == 1)
        #expect(llmRouteAndSummarize.calls.count == 1)
        #expect(llmRouteOnly.calls[0].systemPrompt == llmRouteAndSummarize.calls[0].systemPrompt)
    }

    // MARK: - Folder match maps to correct NotesFolder

    @Test
    func classifiedFolderPathMapsToCorrectNotesFolder() async throws {
        let finance = NotesFolder(id: "f", name: "finance")
        let home = NotesFolder(id: "fh", name: "home")
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [finance], "f": [home], "fh": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "finance.home\nBudget review"

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Reviewed monthly budget", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == home)
    }

    // MARK: - createdInDefaultFolder result: logs reason, marks processed

    @Test
    func createdInDefaultFolderLogsReasonAndMarksProcessed() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .createdInDefaultFolder(reason: "folder was locked")

        let llm = MockLLMService()
        llm.result = "personal\nGrocery list"

        let store = MockMemoStore()
        let logger = MockWatcherLogger()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            logger: logger,
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        let hasReasonLog = logger.infos.contains { $0.contains("folder was locked") }
            || logger.warnings.contains { $0.contains("folder was locked") }
        #expect(hasReasonLog)
        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
    }

    // MARK: - Cleanup always runs exactly once

    @Test
    func markProcessedAndOnCompleteRunExactlyOnceOnSuccessPath() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nGrocery list"

        let store = MockMemoStore()
        let completeCounter = ActorBox(0)
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: MockTranscriptSummarizer(),
            store: store,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute) },
            contextBudget: smallBudget(),
            onComplete: { await completeCounter.increment() }
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(await completeCounter.get() == 1)
    }

    @Test
    func markProcessedAndOnCompleteRunExactlyOnceOnErrorPath() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]

        struct LLMError: Error {}
        let llm = MockLLMService()
        llm.error = LLMError()

        let store = MockMemoStore()
        let completeCounter = ActorBox(0)
        let stage = NoteRoutingPipelineStage(
            notesService: notes,
            llmService: llm,
            summarizer: MockTranscriptSummarizer(),
            store: store,
            logger: MockWatcherLogger(),
            configProvider: { RoutingConfiguration(llmApproach: .autoRoute) },
            contextBudget: smallBudget(),
            onComplete: { await completeCounter.increment() }
        )

        let fileURL = makeURL()
        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: fileURL)
        await stage.route(result)

        let markCalls = await store.markProcessedCalls
        #expect(markCalls.count == 1)
        #expect(markCalls[0].fileURL == fileURL)
        #expect(await completeCounter.get() == 1)
    }

    // MARK: - .disabled LLM approach

    @Test
    func disabledLLMSkipsClassificationAndCreatesNoteWithDateTitle() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let summarizer = MockTranscriptSummarizer()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(llmApproach: .disabled),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.isEmpty)
        #expect(summarizer.calls.isEmpty)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
        #expect(notes.createNoteCalls[0].body == "Buy groceries")
    }

    @Test
    func disabledLLMWithMatchingDefaultFolderCreatesNoteInThatFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(llmApproach: .disabled, defaultFolderName: "personal"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.isEmpty)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == personal)
    }

    @Test
    func disabledLLMWithUnknownDefaultFolderCreatesNoteInSystemDefault() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(llmApproach: .disabled, defaultFolderName: "Gone"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
    }

    @Test
    func disabledLLMWithDefaultFolderWhenHierarchyFetchFailsCreatesNoteInSystemDefault() async throws {
        let notes = MockNotesService()
        struct FetchError: Error {}
        notes.listFoldersError = FetchError()
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(llmApproach: .disabled, defaultFolderName: "personal"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == nil)
    }

    // MARK: - .customPrompt LLM approach

    @Test
    func customPromptApproachCallsLLMWithCustomPrompt() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nGrocery list"
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(llmApproach: .customPrompt("my prompt {notes_folders}")),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.count == 1)
        #expect(llm.calls[0].systemPrompt.contains("my prompt"))
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == personal)
    }

    @Test
    func emptyCustomPromptSkipsLLMAndRoutesToDefaultFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(llmApproach: .customPrompt(""), defaultFolderName: "personal"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(llm.calls.isEmpty)
        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == personal)
    }

    // MARK: - summarizationEnabled flag

    @Test
    func summarizationEnabledTrueUsesSummaryAsBody() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nMeeting notes"

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "condensed"

        let store = MockMemoStore()
        let fullTranscript = "one two three four five"
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(llmApproach: .autoRoute, summarizationEnabled: true),
            contextBudget: tinyBudget()
        )

        let result = TranscriptionResult(transcript: fullTranscript, fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == "condensed")
    }

    @Test
    func summarizationEnabledFalseUsesFullTranscriptAsBody() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "personal\nMeeting notes"

        let summarizer = MockTranscriptSummarizer()
        summarizer.result = "condensed"

        let store = MockMemoStore()
        let fullTranscript = "one two three four five"
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            summarizer: summarizer,
            store: store,
            config: RoutingConfiguration(llmApproach: .autoRoute, summarizationEnabled: false),
            contextBudget: tinyBudget()
        )

        let result = TranscriptionResult(transcript: fullTranscript, fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls[0].body == fullTranscript)
    }

    // MARK: - Unrecognized folder with defaultFolderName

    @Test
    func unrecognizedFolderWithDefaultFolderNameRoutesToDefaultFolder() async throws {
        let personal = makePersonalFolder()
        let notes = MockNotesService()
        notes.listFoldersByParent = [nil: [personal], "personal": []]
        notes.createNoteResult = .created

        let llm = MockLLMService()
        llm.result = "unknown.path\nSome title"  // not in hierarchy

        let store = MockMemoStore()
        let stage = makeStage(
            notesService: notes,
            llmService: llm,
            store: store,
            config: RoutingConfiguration(llmApproach: .autoRoute, defaultFolderName: "personal"),
            contextBudget: smallBudget()
        )

        let result = TranscriptionResult(transcript: "Buy groceries", fileURL: makeURL())
        await stage.route(result)

        #expect(notes.createNoteCalls.count == 1)
        #expect(notes.createNoteCalls[0].folder == personal)
    }
}
