import Foundation

/// Monitors an iCloud Voice Memos sync folder for newly arriving `.m4a` files
/// and emits `VoiceMemoEvent`s for each fully-synced memo.
///
/// - Catalogs existing files on startup without emitting events for them.
/// - Deduplicates: at most one event per file path.
/// - Handles missing/unreadable folders with exponential-backoff polling.
/// - Supports multiple concurrent consumers via `events()`.
@MainActor
public final class VoiceMemoWatcher {
    private let directoryURL: URL
    private let monitor: any DirectoryMonitor
    private let fileSystem: any FileSystemChecker
    private let logger: any WatcherLogger
    private let clock: any Clock<Duration>

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

    /// Begin monitoring the directory for new voice memos.
    public func start() async {
        // Implementation in Task 3
    }

    /// Stop monitoring and complete all event streams.
    public func stop() {
        // Implementation in Task 3
    }

    /// Returns a new async stream of voice memo events.
    /// Each call creates an independent stream — multiple consumers are supported.
    public func events() -> AsyncStream<VoiceMemoEvent> {
        // Implementation in Task 3/6
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
