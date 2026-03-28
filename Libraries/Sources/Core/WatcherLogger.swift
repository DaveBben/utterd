/// Abstracts logging so tests can capture and assert on messages.
/// Production implementation should use `os.Logger`.
public protocol WatcherLogger: Sendable {
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}
