import AppKit
import Core

enum PermissionGateAction {
    case proceed
    case showPermissionAlert
}

@MainActor
func evaluatePermissionGate(checker: PermissionChecker) -> PermissionGateAction {
    checker.checkAccess()
    return checker.hasVoiceMemoAccess ? .proceed : .showPermissionAlert
}

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
    private lazy var permissionChecker = PermissionChecker(fileSystem: RealFileSystemChecker())

    private var voiceMemoWatcher: VoiceMemoWatcher?
    private var pipelineController: PipelineController?
    private var watcherTask: Task<Void, Never>?
    private var controllerTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip permission gate during unit tests to prevent alert from blocking test runner.
        // Works with xcodebuild. Does not detect swift test CLI.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        assert(appState != nil, "appState must be wired by UtterdApp.body before applicationDidFinishLaunching")

        // SwiftUI evaluates App.body (including MenuBarExtra scenes) BEFORE
        // applicationDidFinishLaunching fires. The MenuBarExtra is conditionally
        // included only when permissionResolved is true, preventing a "ghost icon"
        // from appearing before the permission check completes.
        let action = evaluatePermissionGate(checker: permissionChecker)
        if action == .proceed {
            appState?.permissionResolved = true
            startPipeline()
        } else {
            showPermissionAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPipeline()
    }

    // MARK: - Pipeline lifecycle

    // ~3K words ≈ ~4K tokens for Apple's on-device Foundation Model.
    // 200 words reserved for the system prompt (classifier instructions + folder hierarchy listing).
    private static let defaultContextBudget = LLMContextBudget(
        totalWords: 3000,
        systemPromptOverhead: 200,
        summaryReserveRatio: 0.3
    )

    private func startPipeline() {
        guard #available(macOS 26, *) else {
            // On macOS 15–25, transcription and LLM services are unavailable.
            // Without a consumer, the watcher cannot persist detected memos, so
            // there is nothing useful to run.
            OSLogWatcherLogger().warning("macOS 26+ required for transcription and LLM — pipeline not started")
            return
        }

        let logger = OSLogWatcherLogger()
        let fileSystem = RealFileSystemChecker()
        let directoryURL = permissionChecker.voiceMemoDirectoryURL

        guard let storeURL = storeFileURL(logger: logger) else {
            logger.error("Pipeline not started — cannot create data directory")
            return
        }
        let store = JSONMemoStore(fileURL: storeURL)

        let monitor = FSEventsDirectoryMonitor(directoryURL: directoryURL)
        let watcher = VoiceMemoWatcher(
            directoryURL: directoryURL,
            monitor: monitor,
            fileSystem: fileSystem,
            logger: logger
        )
        self.voiceMemoWatcher = watcher

        let controller = makePipelineController(
            store: store, watcher: watcher, logger: logger
        )
        self.pipelineController = controller

        watcherTask = Task { await watcher.start() }
        controllerTask = Task { await controller.start() }
    }

    @available(macOS 26, *)
    private func makePipelineController(
        store: JSONMemoStore,
        watcher: VoiceMemoWatcher,
        logger: OSLogWatcherLogger
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
            makeRoutingStage: { onComplete in
                NoteRoutingPipelineStage(
                    notesService: notesService,
                    llmService: llmService,
                    summarizer: summarizer,
                    store: store,
                    logger: logger,
                    // routeOnly: note body is the full transcript.
                    // routeAndSummarize available but disabled until a user preference toggle exists.
                    mode: .routeOnly,
                    contextBudget: contextBudget,
                    onComplete: onComplete
                )
            }
        )
    }

    private func stopPipeline() {
        // Stop producer (watcher) before consumer (controller) so the event
        // stream finishes cleanly before the consumer is torn down.
        voiceMemoWatcher?.stop()
        watcherTask?.cancel()
        watcherTask = nil
        pipelineController?.stop()
        controllerTask?.cancel()
        controllerTask = nil
    }

    /// Returns the URL for the memo store JSON file in Application Support,
    /// or nil if the directory cannot be created.
    private func storeFileURL(logger: OSLogWatcherLogger) -> URL? {
        // Application Support always exists in userDomainMask on macOS.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
