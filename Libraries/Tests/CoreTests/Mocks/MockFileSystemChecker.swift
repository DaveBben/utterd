import Foundation
@testable import Core

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockFileSystemChecker: FileSystemChecker, @unchecked Sendable {
    nonisolated(unsafe) var existsResult: Bool = true
    nonisolated(unsafe) var readableResult: Bool = true
    nonisolated(unsafe) var directoryContents: [URL] = []
    nonisolated(unsafe) var fileSizes: [URL: Int64] = [:]

    nonisolated(unsafe) var directoryExistsCallCount: Int = 0
    nonisolated(unsafe) var onDirectoryExistsCheck: ((Int) -> Void)?

    func directoryExists(at url: URL) -> Bool {
        directoryExistsCallCount += 1
        onDirectoryExistsCheck?(directoryExistsCallCount)
        return existsResult
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
