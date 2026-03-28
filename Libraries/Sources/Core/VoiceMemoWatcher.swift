import Foundation

@MainActor
public final class VoiceMemoWatcher {
    public let directoryURL: URL
    let monitor: any DirectoryMonitor
    let fileSystem: any FileSystemChecker
    let logger: any WatcherLogger
    let clock: any Clock<Duration>

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
    }

    public func stop() {
    }

    public func events() -> AsyncStream<VoiceMemoEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
