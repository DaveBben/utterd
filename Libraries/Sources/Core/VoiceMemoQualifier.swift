import Foundation

public struct VoiceMemoQualifier: Sendable {
    public static func qualifies(url: URL, fileSize: Int64) -> VoiceMemoEvent? {
        let filename = url.lastPathComponent
        guard !filename.hasPrefix(".") else { return nil }
        guard url.pathExtension.lowercased() == "m4a" else { return nil }
        guard fileSize > 1024 else { return nil }
        return VoiceMemoEvent(fileURL: url, fileSize: fileSize)
    }
}
