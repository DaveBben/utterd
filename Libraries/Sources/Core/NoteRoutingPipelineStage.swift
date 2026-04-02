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
        let transcript = result.transcript
        let fileURL = result.fileURL
        let now = Date()

        do {
            try await routeCore(transcript: transcript, now: now)
        } catch {
            logger.error("Note routing failed: \(error)")
        }

        // Cleanup always runs regardless of success or failure — not a defer because
        // defer cannot contain await in Swift.
        do {
            try await store.markProcessed(fileURL: fileURL, date: now)
        } catch {
            logger.error("NoteRoutingPipelineStage: failed to mark processed \(fileURL.lastPathComponent): \(error)")
        }
        await onComplete()
    }

    // MARK: - Private

    private func routeCore(transcript: String, now: Date) async throws {
        // Empty transcript: skip classification, create note in default folder
        if transcript.isEmpty {
            _ = try await notesService.createNote(
                title: dateFallbackTitle(for: now),
                body: "",
                in: nil
            )
            return
        }

        // Build folder hierarchy; if empty, skip classification
        let hierarchy = try await buildFolderHierarchy(using: notesService)
        guard !hierarchy.isEmpty else {
            _ = try await notesService.createNote(
                title: dateFallbackTitle(for: now),
                body: transcript,
                in: nil
            )
            return
        }

        // Determine text for classification: summarize if transcript exceeds budget
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

        // Classify
        let classification = try await TranscriptClassifier.classify(
            transcript: classificationText,
            hierarchy: hierarchy,
            using: llmService,
            now: now
        )
        // Resolve folder (nil for GENERAL NOTES or unrecognized paths)
        let folder = classification.folderPath.flatMap { path in
            hierarchy.first { $0.path == path }?.folder
        }

        // Determine note body based on mode
        let body: String
        switch mode {
        case .routeOnly:
            body = transcript
        case .routeAndSummarize:
            body = summary ?? transcript
        }

        // Sanitize the LLM-derived title: cap length, strip control characters
        let sanitizedTitle: String = {
            let truncated = String(classification.title.prefix(100))
                .filter { !$0.isNewline && $0 != "\0" && $0 != "\t" }
            return truncated.isEmpty ? dateFallbackTitle(for: now) : truncated
        }()

        logger.info("LLM classification — folder: \(classification.folderPath ?? "GENERAL NOTES"), title: \(sanitizedTitle)")
        logger.info("Creating note '\(sanitizedTitle)' in \(folder?.name ?? "default folder") with \(body.count) char body")

        // Create note
        let creationResult = try await notesService.createNote(
            title: sanitizedTitle,
            body: body,
            in: folder
        )
        if case .createdInDefaultFolder(let reason) = creationResult {
            logger.warning("Note created in default folder: \(reason)")
        }
    }
}

