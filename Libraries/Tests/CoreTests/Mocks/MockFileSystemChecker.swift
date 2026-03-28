import Foundation
@testable import Core

/// A test double for `FileSystemChecker` with configurable return values
/// for all filesystem queries.
final class MockFileSystemChecker: FileSystemChecker, @unchecked Sendable {
    /// Return value for `directoryExists(at:)`.
    var existsResult: Bool = true

    /// Return value for `isReadable(at:)`.
    var readableResult: Bool = true

    /// Return value for `contentsOfDirectory(at:)`.
    var directoryContents: [URL] = []

    /// Per-URL file sizes. Return value for `fileSize(at:)`.
    var fileSizes: [URL: Int64] = [:]

    func directoryExists(at url: URL) -> Bool {
        existsResult
    }

    func isReadable(at url: URL) -> Bool {
        readableResult
    }

    func contentsOfDirectory(at url: URL) -> [URL] {
        directoryContents
    }

    func fileSize(at url: URL) -> Int64? {
        fileSizes[url]
    }
}
