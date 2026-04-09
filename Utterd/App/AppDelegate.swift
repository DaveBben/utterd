import AppKit
import Core

enum PermissionGateAction {
    case proceed
    case showPermissionAlert
    case showDirectoryMissingAlert
}

@MainActor
func evaluatePermissionGate(fileSystem: FileSystemChecker) -> PermissionGateAction {
    let url = voiceMemoDirectoryURL
    guard fileSystem.directoryExists(at: url) else {
        return .showDirectoryMissingAlert
    }
    // Attempt a directory listing to trigger TCC registration so Utterd
    // appears in System Settings > Full Disk Access.
    _ = fileSystem.contentsOfDirectory(at: url)
    return fileSystem.isReadable(at: url) ? .proceed : .showPermissionAlert
}

let voiceMemoDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")

@MainActor
func handleOpenSystemSettings(
    openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) },
    terminate: () -> Void = { NSApplication.shared.terminate(nil) }
) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
        _ = openURL(url)
    }
    terminate()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Written once by UtterdApp.body before applicationDidFinishLaunching fires.
    var appState: AppState?
    private let fileSystem: FileSystemChecker = RealFileSystemChecker()

    private var voiceMemoWatcher: VoiceMemoWatcher?
    private var pipelineController: PipelineController?
    private var watcherTask: Task<Void, Never>?
    private var controllerTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip permission gate during unit tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        assert(appState != nil, "appState must be wired by UtterdApp.body before applicationDidFinishLaunching")

        let action = evaluatePermissionGate(fileSystem: fileSystem)
        switch action {
        case .proceed:
            appState?.permissionResolved = true
            startPipeline()
        case .showPermissionAlert:
            showPermissionAlert()
        case .showDirectoryMissingAlert:
            showDirectoryMissingAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPipeline()
    }

    // MARK: - Pipeline lifecycle

    // swiftlint:disable:next force_try — hardcoded valid constants
    private static let defaultContextBudget = try! LLMContextBudget(
        totalWords: 3000,
        systemPromptOverhead: 200,
        summaryReserveRatio: 0.3
    )

    private func startPipeline() {
        guard #available(macOS 26, *) else {
            OSLogWatcherLogger().warning("macOS 26+ required for transcription and LLM — pipeline not started")
            return
        }

        let osLogger = OSLogWatcherLogger()
        guard let (logger, store) = makeLoggerAndStore(osLogger: osLogger) else {
            osLogger.error("Pipeline not started — cannot create data directory")
            return
        }

        Task { [weak self] in
            let record = await store.mostRecentlyProcessed()
            await MainActor.run { self?.appState?.lastProcessedDate = record?.dateProcessed }
        }

        let monitor = FSEventsDirectoryMonitor(directoryURL: voiceMemoDirectoryURL)
        let watcher = VoiceMemoWatcher(
            directoryURL: voiceMemoDirectoryURL, monitor: monitor,
            fileSystem: fileSystem, logger: logger
        )
        self.voiceMemoWatcher = watcher

        let controller = makePipelineController(store: store, watcher: watcher, logger: logger)
        self.pipelineController = controller

        watcherTask = Task { await watcher.start() }
        controllerTask = Task { await controller.start() }
    }

    private func makeLoggerAndStore(osLogger: OSLogWatcherLogger) -> (any WatcherLogger, JSONMemoStore)? {
        guard let storeURL = storeFileURL(logger: osLogger) else { return nil }
        let logURL = storeURL.deletingLastPathComponent().appendingPathComponent("utterd.log")
        let fileLogger = FileWatcherLogger(fileURL: logURL)
        let logger = CompositeWatcherLogger([osLogger, fileLogger])
        let store = JSONMemoStore(fileURL: storeURL, logger: logger)
        return (logger, store)
    }

    @available(macOS 26, *)
    private func makePipelineController(
        store: JSONMemoStore,
        watcher: VoiceMemoWatcher,
        logger: any WatcherLogger
    ) -> PipelineController {
        let transcriptionService = SpeechAnalyzerTranscriptionService()
        let notesService = AppleScriptNotesService()
        let llmService = FoundationModelLLMService()
        let summarizer = IterativeRefineSummarizer(llmService: llmService)
        let contextBudget = Self.defaultContextBudget

        return PipelineController(
            store: store,
            transcriptionService: transcriptionService,
            watcherStream: watcher.events(),
            logger: logger,
            makeRoutingStage: {
                let configProvider: @Sendable () -> RoutingConfiguration = {
                    UserSettings.readRoutingConfiguration()
                }
                return NoteRoutingPipelineStage(
                    notesService: notesService,
                    llmService: llmService,
                    summarizer: summarizer,
                    store: store,
                    logger: logger,
                    configProvider: configProvider,
                    contextBudget: contextBudget
                )
            },
            onItemProcessed: { [weak self] in
                await MainActor.run { self?.appState?.lastProcessedDate = Date() }
            }
        )
    }

    private func stopPipeline() {
        voiceMemoWatcher?.stop()
        watcherTask?.cancel()
        watcherTask = nil
        pipelineController?.stop()
        controllerTask?.cancel()
        controllerTask = nil
    }

    private func storeFileURL(logger: OSLogWatcherLogger) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Application Support directory not found")
            return nil
        }
        let dir = appSupport.appendingPathComponent("Utterd", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Application Support directory: \(error)")
            return nil
        }
        return dir.appendingPathComponent("memo-store.json")
    }

    // MARK: - Permission alert

    private func showDirectoryMissingAlert() {
        NSApplication.shared.terminate(nil)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = "Utterd needs to read voice memos from iCloud. Please grant Full Disk Access in System Settings > Privacy & Security > Full Disk Access, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        let quitButton = alert.addButton(withTitle: "Quit")
        quitButton.keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            handleOpenSystemSettings()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
}
