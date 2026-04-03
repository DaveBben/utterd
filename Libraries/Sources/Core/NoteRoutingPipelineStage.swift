import Foundation

/// Pipeline Stage 2: routes a transcription result into a Notes folder
/// and creates the note. Calls `onComplete` after every code path to release
/// the pipeline lock.
public final class NoteRoutingPipelineStage: Sendable {
    private let notesService: any NotesService
    private let llmService: any LLMService
    private let summarizer: any TranscriptSummarizer
    private let store: any MemoStore
    private let logger: any WatcherLogger
    private let configProvider: @Sendable () -> RoutingConfiguration
    private let contextBudget: LLMContextBudget
    private let onComplete: @Sendable () async -> Void

    public init(
        notesService: any NotesService,
        llmService: any LLMService,
        summarizer: any TranscriptSummarizer,
        store: any MemoStore,
        logger: any WatcherLogger,
        configProvider: @escaping @Sendable () -> RoutingConfiguration,
        contextBudget: LLMContextBudget,
        onComplete: @escaping @Sendable () async -> Void
    ) {
        self.notesService = notesService
        self.llmService = llmService
        self.summarizer = summarizer
        self.store = store
        self.logger = logger
        self.configProvider = configProvider
        self.contextBudget = contextBudget
        self.onComplete = onComplete
    }

    public func route(_ result: TranscriptionResult) async {
        let transcript = result.transcript
        let fileURL = result.fileURL
        let now = Date()

        do {
            try await routeCore(transcript: transcript, now: now)
        } catch {
            logger.error("Note routing failed: \(error)")
        }

        do {
            try await store.markProcessed(fileURL: fileURL, date: now)
        } catch {
            logger.error("NoteRoutingPipelineStage: failed to mark processed \(fileURL.lastPathComponent): \(error)")
        }
        await onComplete()
    }

    // MARK: - Private

    private func routeCore(transcript: String, now: Date) async throws {
        let config = configProvider()
        let folder = await resolveDefaultFolder(config.defaultFolderName)
        var body = transcript
        let title = dateFallbackTitle(for: now)

        if config.summarizationEnabled && !transcript.isEmpty {
            do {
                let summary = try await summarizer.summarize(
                    transcript: transcript,
                    contextBudget: contextBudget
                )
                if !summary.isEmpty {
                    body = summary
                }
            } catch {
                logger.error("Summarization failed, using full transcript: \(error)")
            }
        }

        // TODO: Task 3 — title generation

        let creationResult = try await notesService.createNote(
            title: title,
            body: body,
            in: folder
        )
        if case .createdInDefaultFolder(let reason) = creationResult {
            logger.warning("Note created in default folder: \(reason)")
        }
    }

    private func resolveDefaultFolder(_ name: String?) async -> NotesFolder? {
        guard let name else { return nil }
        do {
            let folders = try await notesService.listFolders(in: nil)
            return folders.first { $0.name == name }
        } catch {
            logger.warning("Default folder resolution failed, using system default: \(error)")
            return nil
        }
    }
}
