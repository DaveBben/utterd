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
        logger.info("Routing started — summarization: \(config.summarizationEnabled), title generation: \(config.titleGenerationEnabled), default folder: \(config.defaultFolderName ?? "(system default)")")
        let folder = await resolveDefaultFolder(config.defaultFolderName)
        var body = transcript
        var title = dateFallbackTitle(for: now)

        if config.summarizationEnabled && !transcript.isEmpty {
            logger.info("LLM summarization started")
            do {
                let summary = try await summarizer.summarize(
                    transcript: transcript,
                    contextBudget: contextBudget
                )
                if !summary.isEmpty {
                    body = summary
                }
                logger.info("LLM summarization completed (\(body.count) chars)")
            } catch {
                logger.error("Summarization failed, using full transcript: \(error)")
            }
        }

        if config.titleGenerationEnabled && !transcript.isEmpty {
            do {
                let truncatedInput = transcript.split(separator: " ").prefix(2000).joined(separator: " ")
                let systemPrompt = "Generate a short descriptive title for this voice memo transcript. Return only the title, nothing else."
                let response = try await llmService.generate(
                    systemPrompt: systemPrompt,
                    userPrompt: truncatedInput
                )
                let firstLine = response.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
                let sanitized = String(firstLine.filter { !$0.isNewline && $0 != "\0" && $0 != "\t" }.prefix(100))
                if !sanitized.isEmpty {
                    title = sanitized
                }
            } catch {
                logger.error("Title generation failed, using date-based title: \(error)")
            }
        }

        logger.info("Creating note '\(title)' in \(folder?.name ?? "system default folder") (\(body.count) char body)")
        let creationResult = try await notesService.createNote(
            title: title,
            body: body,
            in: folder
        )
        if case .createdInDefaultFolder(let reason) = creationResult {
            logger.warning("Note created in default folder: \(reason)")
        }
        logger.info("Note created successfully")
    }

    private func resolveDefaultFolder(_ name: String?) async -> NotesFolder? {
        guard let name, !name.isEmpty else { return nil }
        do {
            let folders = try await notesService.listFolders(in: nil)
            return folders.first { $0.name == name }
        } catch {
            logger.warning("Default folder resolution failed, using system default: \(error)")
            return nil
        }
    }
}
