import Foundation

/// Abstracts filesystem directory monitoring so that tests can inject
/// a mock instead of relying on real FSEvents.
public protocol DirectoryMonitor: Sendable {
    /// Begin monitoring the directory. Throws if the directory cannot be monitored.
    func start() throws

    /// Stop monitoring and complete the event stream.
    func stop()

    /// An asynchronous stream of change notifications. Each element is the set
    /// of file URLs that changed since the last notification.
    var events: AsyncStream<Set<URL>> { get }
}
