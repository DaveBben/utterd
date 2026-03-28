import Foundation

/// Abstracts filesystem queries so tests can control directory state
/// without touching the real filesystem.
public protocol FileSystemChecker: Sendable {
    func directoryExists(at url: URL) -> Bool
    func isReadable(at url: URL) -> Bool
    func contentsOfDirectory(at url: URL) -> [URL]
    /// Returns the file size in bytes, or `nil` if the file does not exist or cannot be stat'd.
    func fileSize(at url: URL) -> Int64?
}
