import Foundation

/// Abstracts filesystem queries so tests can control directory state
/// without touching the real filesystem.
public protocol FileSystemChecker: Sendable {
    func directoryExists(at url: URL) -> Bool
    func isReadable(at url: URL) -> Bool
    /// Returns the immediate children of the directory at `url` (non-recursive).
    /// Returns an empty array if the directory does not exist, is not readable,
    /// or an I/O error occurs — callers cannot distinguish errors from empty directories.
    func contentsOfDirectory(at url: URL) -> [URL]
    /// Returns the file size in bytes, or `nil` if the file does not exist or cannot be stat'd.
    func fileSize(at url: URL) -> Int64?
}
