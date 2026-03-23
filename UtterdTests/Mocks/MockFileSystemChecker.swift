// NOTE: Parallels Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift.
// If FileSystemChecker gains new methods, both mocks must be updated.
import Core
import Foundation

final class MockFileSystemChecker: FileSystemChecker, @unchecked Sendable {
    nonisolated(unsafe) var readableResult: Bool = true
    nonisolated(unsafe) var isReadableCalledWith: [URL] = []

    func isReadable(at url: URL) -> Bool {
        isReadableCalledWith.append(url)
        return readableResult
    }

    func directoryExists(at url: URL) -> Bool { true }
    func contentsOfDirectory(at url: URL) -> [URL] { [] }
    func fileSize(at url: URL) -> Int64? { nil }
}
