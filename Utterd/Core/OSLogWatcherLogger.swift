import Core
import os

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
