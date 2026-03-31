import Foundation

/// Pipeline Stage 2: classifies a transcription result into a Notes folder
/// and creates the note. Calls `onComplete` after every code path to release
/// the pipeline lock.
public final class NoteRoutingPipelineStage: Sendable {
    private let notesService: any NotesService
    private let llmService: any LLMService
    private let summarizer: any TranscriptSummarizer
    private let store: any MemoStore
    private let logger: any WatcherLogger
    private let mode: RoutingMode
    private let contextBudget: LLMContextBudget
    private let onComplete: @Sendable () async -> Void

    public init(
        notesService: any NotesService,
        llmService: any LLMService,
        summarizer: any TranscriptSummarizer,
        store: any MemoStore,
        logger: any WatcherLogger,
        mode: RoutingMode,
        contextBudget: LLMContextBudget,
        onComplete: @escaping @Sendable () async -> Void
    ) {
        self.notesService = notesService
        self.llmService = llmService
        self.summarizer = summarizer
        self.store = store
        self.logger = logger
        self.mode = mode
        self.contextBudget = contextBudget
        self.onComplete = onComplete
    }

    public func route(_ result: TranscriptionResult) async {
        // Implementation in Task 5
    }
}
