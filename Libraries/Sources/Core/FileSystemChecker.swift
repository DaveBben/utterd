import Foundation

public protocol FileSystemChecker: Sendable {
    func directoryExists(at url: URL) -> Bool
    func isReadable(at url: URL) -> Bool
    func contentsOfDirectory(at url: URL) -> [URL]
    func fileSize(at url: URL) -> Int64?
}
