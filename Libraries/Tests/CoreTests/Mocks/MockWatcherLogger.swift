@testable import Core

/// A test double for `WatcherLogger` that captures log messages
/// for assertion in tests.
final class MockWatcherLogger: WatcherLogger, @unchecked Sendable {
    var infos: [String] = []
    var warnings: [String] = []
    var errors: [String] = []

    func info(_ message: String) {
        infos.append(message)
    }

    func warning(_ message: String) {
        warnings.append(message)
    }

    func error(_ message: String) {
        errors.append(message)
    }
}
