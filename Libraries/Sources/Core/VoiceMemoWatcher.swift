import Foundation

@MainActor
public final class VoiceMemoWatcher {
    public let directoryURL: URL
    let monitor: any DirectoryMonitor
    let fileSystem: any FileSystemChecker
    let logger: any WatcherLogger
    let clock: any Clock<Duration>

    // Maps each known file URL to its last-evaluated size.
    // nil = cataloged but not yet qualified/emitted.
    private var seen: [URL: Int64?] = [:]

    // Tracks files for which an event has been emitted — permanently deduplicates.
    private var emittedPaths: Set<URL> = []

    // Single consumer continuation — replaced each time events() is called.
    private var eventContinuation: AsyncStream<VoiceMemoEvent>.Continuation?

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

    public func start() async {
        // Catalog existing files — suppress events for files already present.
        for url in fileSystem.contentsOfDirectory(at: directoryURL) {
            let size = fileSystem.fileSize(at: url)
            if let size, let _ = VoiceMemoQualifier.qualifies(url: url, fileSize: size) {
                // Already qualifies — mark as emitted so it is never re-emitted.
                emittedPaths.insert(url)
                seen[url] = size
            } else {
                // Not yet qualifying — store nil so it can be re-evaluated on growth.
                seen[url] = nil
            }
        }

        guard let eventStream = try? monitor.start() else { return }

        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await changedURLs in eventStream {
                self.handle(changedURLs: changedURLs)
            }
        }
    }

    public func stop() {
        monitor.stop()
        monitorTask?.cancel()
        monitorTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
    }

    public func events() -> AsyncStream<VoiceMemoEvent> {
        let (stream, continuation) = AsyncStream<VoiceMemoEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        eventContinuation = continuation
        return stream
    }

    private func handle(changedURLs: Set<URL>) {
        for url in changedURLs {
            guard let size = fileSystem.fileSize(at: url) else {
                // File deleted or inaccessible — skip silently.
                continue
            }

            guard !emittedPaths.contains(url) else {
                // Already emitted for this path — deduplicate.
                continue
            }

            if let event = VoiceMemoQualifier.qualifies(url: url, fileSize: size) {
                emittedPaths.insert(url)
                seen[url] = size
                eventContinuation?.yield(event)
                logger.info("Detected \(url.lastPathComponent) (\(size) bytes)")
            } else {
                // Not yet qualifying — track with nil so it can be re-evaluated.
                seen[url] = nil
            }
        }
    }
}
