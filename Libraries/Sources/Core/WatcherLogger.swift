/// Logging abstraction for test assertion on log messages.
public protocol WatcherLogger: Sendable {
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}
