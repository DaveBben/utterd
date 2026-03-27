import CoreServices
import Foundation

/// Errors that can occur when setting up or running the directory watcher.
public enum DirectoryWatcherError: Error, Sendable {
    /// The specified directory does not exist.
    case directoryNotFound(URL)
    /// The specified path exists but is not a directory.
    case notADirectory(URL)
    /// Insufficient permissions to read the directory.
    case permissionDenied(URL)
    /// The watched directory was deleted while the watcher was running.
    case directoryDeleted(URL)
}

/// Monitors a directory for new `.m4a` files and emits their URLs via an async stream.
///
/// The watcher begins monitoring when created and stops when the `events` stream
/// is cancelled (by the consuming task being cancelled) or when the watched directory
/// is deleted.
///
/// Only files that appear *after* the watcher starts are emitted. Pre-existing files
/// are ignored. Each file path is emitted at most once per watcher session.
public struct DirectoryWatcher: Sendable {
    /// An async stream of URLs for new `.m4a` files detected in the watched directory.
    public let events: AsyncStream<URL>

    /// Creates a watcher that monitors `directory` for new `.m4a` files.
    ///
    /// - Parameter directory: The directory to watch. Must exist and be readable.
    /// - Throws: `DirectoryWatcherError` if the directory is invalid or inaccessible.
    public init(directory: URL) throws {
        // Stub — implementation provided in Task 2
        events = AsyncStream { $0.finish() }
    }
}
