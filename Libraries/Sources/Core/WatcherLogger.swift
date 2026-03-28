/// Abstracts logging so that tests can capture and assert on log messages
/// instead of relying on os.Logger output.
public protocol WatcherLogger: Sendable {
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}
