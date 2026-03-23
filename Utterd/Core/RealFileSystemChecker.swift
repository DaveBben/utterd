import Core
import Foundation
import OSLog

struct RealFileSystemChecker: FileSystemChecker {
    private static let logger = Logger(subsystem: "com.bennett.Utterd", category: "FileSystem")
    func isReadable(at url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    func contentsOfDirectory(at url: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
        } catch {
            Self.logger.warning("contentsOfDirectory failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fileSize(at url: URL) -> Int64? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
    }
}
