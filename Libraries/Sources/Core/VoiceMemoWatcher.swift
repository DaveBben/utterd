import Foundation

/// Monitors a directory for new voice memos and emits ``VoiceMemoEvent``s.
///
/// Catalogs existing files on startup (no events emitted for them). Handles
/// missing or unreadable directories with exponential-backoff polling (5s–60s).
/// Supports multiple concurrent consumers via ``events()``.
@MainActor
public final class VoiceMemoWatcher {
    public let directoryURL: URL
    private let monitor: any DirectoryMonitor
    private let fileSystem: any FileSystemChecker
    private let logger: any WatcherLogger
    private let clock: any Clock<Duration>

    // Tracks files for which an event has been emitted — permanently deduplicates.
    private var emittedPaths: Set<URL> = []

    // Continuation registry — each events() call gets its own entry.
    private var continuations: [UUID: AsyncStream<VoiceMemoEvent>.Continuation] = [:]

    // The running monitor loop task — cancelled by stop().
    private var monitorTask: Task<Void, Never>?

    public init(
        directoryURL: URL,
        monitor: any DirectoryMonitor,
        fileSystem: any FileSystemChecker,
        logger: any WatcherLogger,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.directoryURL = directoryURL
        self.monitor = monitor
        self.fileSystem = fileSystem
        self.logger = logger
        self.clock = clock
    }

    /// Begins monitoring. Returns promptly — the monitoring loop runs as a background task.
    /// Logs a warning (missing folder) or error (no read permission) before returning.
    /// If the folder is unavailable, polls with exponential backoff until it appears.
    public func start() async {
        // Cancel any existing monitoring task to prevent orphaned loops.
        if monitorTask != nil {
            stop()
        }

        // Check initial state synchronously so tests can assert on log messages
        // immediately after start() returns.
        if !fileSystem.directoryExists(at: directoryURL) {
            logger.warning("Watched folder is missing: \(directoryURL.path)")
        } else if !fileSystem.isReadable(at: directoryURL) {
            logger.error("Watched folder is not readable (permission denied): \(directoryURL.path)")
        }

        // Launch the monitoring lifecycle as a background task so start() returns promptly.
        monitorTask = Task { [weak self] in
            guard let self else { return }

            // Re-check availability inside the task (state may have changed).
            if !fileSystem.directoryExists(at: directoryURL)
                || !fileSystem.isReadable(at: directoryURL)
            {
                await pollUntilAvailable()
            }
            guard !Task.isCancelled else { return }

            // Main monitoring loop: run → detect folder loss → poll → run again.
            while !Task.isCancelled {
                let shouldRetry = await runMonitoringLoop()
                if !shouldRetry { break }

                // Folder disappeared — clear dedup state so re-created files
                // at the same path are detected after recovery.
                emittedPaths.removeAll()

                await pollUntilAvailable()
            }
        }

        // Yield once so the monitorTask has a chance to start.
        await Task.yield()
    }

    /// Stops monitoring, cancels the background task, and finishes all consumer streams.
    /// Safe to call multiple times.
    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        monitor.stop()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    /// Returns a new independent async stream of voice memo events. Each call
    /// creates a separate stream — multiple consumers are supported (broadcast).
    /// Late joiners do not receive historical events. Uses `.bufferingOldest(16)`.
    public func events() -> AsyncStream<VoiceMemoEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            DispatchQueue.main.async {
                self?.continuations.removeValue(forKey: id)
            }
        }
        return stream
    }

    // MARK: - Private

    /// Polls until the directory exists and is readable, using exponential backoff.
    private func pollUntilAvailable() async {
        var backoff = Duration.seconds(5)
        let cap = Duration.seconds(60)

        while !Task.isCancelled {
            try? await clock.sleep(for: backoff)
            guard !Task.isCancelled else { return }

            let nowExists = fileSystem.directoryExists(at: directoryURL)
            if nowExists && fileSystem.isReadable(at: directoryURL) {
                return
            }

            backoff = min(backoff * 2, cap)
        }
    }

    /// Catalogs existing files, starts the monitor, and processes events.
    /// Returns `true` if the folder disappeared and the caller should retry,
    /// `false` if monitoring ended normally (stop() was called).
    private func runMonitoringLoop() async -> Bool {
        guard !Task.isCancelled else { return false }

        // Catalog existing files — suppress events for files already present.
        for url in fileSystem.contentsOfDirectory(at: directoryURL) {
            let size = fileSystem.fileSize(at: url)
            if let size, VoiceMemoQualifier.qualifies(url: url, fileSize: size) != nil {
                emittedPaths.insert(url)
            }
        }

        let eventStream: AsyncStream<Set<URL>>
        do {
            eventStream = try monitor.start()
        } catch {
            logger.error("Failed to start directory monitor: \(error)")
            return false
        }

        logger.info("Monitoring started")

        for await changedURLs in eventStream {
            guard !Task.isCancelled else { break }
            handle(changedURLs: changedURLs)
        }

        guard !Task.isCancelled else { return false }

        // Stream ended — check whether the directory disappeared.
        monitor.stop()
        let stillExists = fileSystem.directoryExists(at: directoryURL)
        if !stillExists {
            logger.error("Watched folder disappeared: \(directoryURL.path)")
            return true // caller should retry after waiting
        }
        return false
    }

    private func handle(changedURLs: Set<URL>) {
        for url in changedURLs {
            guard let size = fileSystem.fileSize(at: url) else {
                continue
            }

            guard !emittedPaths.contains(url) else {
                continue
            }

            if let event = VoiceMemoQualifier.qualifies(url: url, fileSize: size) {
                emittedPaths.insert(url)
                broadcast(event)
                logger.info("Detected \(url.lastPathComponent) (\(size) bytes)")
            }
        }
    }

    private func broadcast(_ event: VoiceMemoEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
}
