import Core
import os

/// Production ``WatcherLogger`` backed by Apple's unified logging system (`os.Logger`).
/// Messages appear in Console.app under the "com.bennett.Utterd" subsystem.
/// Uses `.auto` privacy so dynamic strings (e.g. file paths) are redacted in the
/// system log unless a debugger is attached at the time of logging.
struct OSLogWatcherLogger: WatcherLogger {
    private let logger = Logger(subsystem: "com.bennett.Utterd", category: "Pipeline")

    func info(_ message: String) {
        logger.info("\(message, privacy: .auto)")
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .auto)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .auto)")
    }
}
