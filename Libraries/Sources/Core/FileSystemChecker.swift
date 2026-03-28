import Foundation

/// Abstracts filesystem queries so that tests can control directory state
/// without touching the real filesystem.
public protocol FileSystemChecker: Sendable {
    /// Returns `true` if a directory exists at the given URL.
    func directoryExists(at url: URL) -> Bool

    /// Returns `true` if the app has read permission for the given URL.
    func isReadable(at url: URL) -> Bool

    /// Returns the URLs of items in the directory, or an empty array if the
    /// directory cannot be read.
    func contentsOfDirectory(at url: URL) -> [URL]

    /// Returns the file size in bytes, or `nil` if the file does not exist
    /// or cannot be stat'd.
    func fileSize(at url: URL) -> Int64?
}
