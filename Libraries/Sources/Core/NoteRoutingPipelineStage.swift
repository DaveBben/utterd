import Foundation

private actor FolderHierarchyCache {
    private var entries: [FolderHierarchyEntry]?
    private var fetchedAt: Date?

    func get(using notesService: any NotesService, ttl: Duration) async throws -> [FolderHierarchyEntry] {
        let ttlSeconds = Double(ttl.components.seconds)
        if let entries, let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttlSeconds {
            return entries
        }
        let fresh = try await buildFolderHierarchy(using: notesService)
        self.entries = fresh
        self.fetchedAt = Date()
        return fresh
    }
}

/// Pipeline Stage 2: classifies a transcription result into a Notes folder
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
    private let folderCache = FolderHierarchyCache()

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
        let mode: RoutingMode = config.summarizationEnabled ? .routeAndSummarize : .routeOnly

        let hierarchy: [FolderHierarchyEntry]
        do {
            hierarchy = try await folderCache.get(using: notesService, ttl: .seconds(300))
        } catch {
            logger.warning("Folder hierarchy fetch failed, using system default: \(error)")
            hierarchy = []
        }
        let defaultFolder = resolveDefaultFolder(config.defaultFolderName, from: hierarchy)

        switch config.llmApproach {
        case .disabled:
            _ = try await notesService.createNote(
                title: dateFallbackTitle(for: now),
                body: transcript,
                in: defaultFolder
            )
            return

        case .customPrompt(let prompt) where prompt.isEmpty:
            _ = try await notesService.createNote(
                title: dateFallbackTitle(for: now),
                body: transcript,
                in: defaultFolder
            )
            return

        case .autoRoute, .customPrompt:
            break
        }

        if transcript.isEmpty {
            _ = try await notesService.createNote(
                title: dateFallbackTitle(for: now),
                body: "",
                in: defaultFolder
            )
            return
        }

        guard !hierarchy.isEmpty else {
            _ = try await notesService.createNote(
                title: dateFallbackTitle(for: now),
                body: transcript,
                in: defaultFolder
            )
            return
        }

        let wordCount = transcript.split(separator: " ").count
        let needsSummarization = wordCount > contextBudget.availableForContent
        let classificationText: String
        let summary: String?
        if needsSummarization {
            let condensed = try await summarizer.summarize(
                transcript: transcript,
                contextBudget: contextBudget
            )
            classificationText = condensed
            summary = condensed
        } else {
            classificationText = transcript
            summary = nil
        }

        let customPrompt: String?
        if case .customPrompt(let prompt) = config.llmApproach {
            customPrompt = prompt
        } else {
            customPrompt = nil
        }

        let classification = try await TranscriptClassifier.classify(
            transcript: classificationText,
            hierarchy: hierarchy,
            using: llmService,
            customSystemPrompt: customPrompt,
            now: now
        )

        let folder: NotesFolder?
        if let path = classification.folderPath {
            folder = hierarchy.first { $0.path == path }?.folder ?? defaultFolder
        } else {
            folder = defaultFolder
        }

        let body: String
        switch mode {
        case .routeOnly:
            body = transcript
        case .routeAndSummarize:
            body = summary ?? transcript
        }

        let sanitizedTitle: String = {
            let truncated = String(classification.title.prefix(100))
                .filter { !$0.isNewline && $0 != "\0" && $0 != "\t" }
            return truncated.isEmpty ? dateFallbackTitle(for: now) : truncated
        }()

        logger.info("LLM classification — folder: \(classification.folderPath ?? "GENERAL NOTES"), title: \(sanitizedTitle)")
        logger.info("Creating note '\(sanitizedTitle)' in \(folder?.name ?? "default folder") with \(body.count) char body")

        let creationResult = try await notesService.createNote(
            title: sanitizedTitle,
            body: body,
            in: folder
        )
        if case .createdInDefaultFolder(let reason) = creationResult {
            logger.warning("Note created in default folder: \(reason)")
        }
    }

    private func resolveDefaultFolder(_ name: String?, from hierarchy: [FolderHierarchyEntry]) -> NotesFolder? {
        guard let name else { return nil }
        return hierarchy.filter { !$0.path.contains(".") }.first { $0.folder.name == name }?.folder
    }
}
