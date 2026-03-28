import Foundation

public protocol DirectoryMonitor: Sendable {
    func start() throws -> AsyncStream<Set<URL>>
    func stop()
}
