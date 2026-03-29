import Core
import Foundation

struct RealFileSystemChecker: FileSystemChecker {
    func isReadable(at url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    func contentsOfDirectory(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    func fileSize(at url: URL) -> Int64? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
    }
}
