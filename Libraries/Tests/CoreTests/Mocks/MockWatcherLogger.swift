@testable import Core

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockWatcherLogger: WatcherLogger, @unchecked Sendable {
    nonisolated(unsafe) var infos: [String] = []
    nonisolated(unsafe) var warnings: [String] = []
    nonisolated(unsafe) var errors: [String] = []

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
