import Foundation
@testable import Core

@MainActor
func makeWatcher(
    directoryURL: URL = URL(fileURLWithPath: "/tmp/memos"),
    monitor: MockDirectoryMonitor = MockDirectoryMonitor(),
    fileSystem: MockFileSystemChecker = MockFileSystemChecker(),
    logger: MockWatcherLogger = MockWatcherLogger()
) -> VoiceMemoWatcher {
    VoiceMemoWatcher(
        directoryURL: directoryURL,
        monitor: monitor,
        fileSystem: fileSystem,
        logger: logger
    )
}
