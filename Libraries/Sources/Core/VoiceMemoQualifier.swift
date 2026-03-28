import Foundation

/// Determines whether a file represents a fully-synced voice memo ready for processing.
/// Rules: must be `.m4a`, filename must not start with `.` (iCloud placeholders like
/// `.memo.m4a.icloud`), and size must exceed 1024 bytes (stubs and truncated syncs are smaller).
public struct VoiceMemoQualifier: Sendable {
    public static func qualifies(url: URL, fileSize: Int64) -> VoiceMemoEvent? {
        let filename = url.lastPathComponent
        guard !filename.hasPrefix(".") else { return nil }
        guard url.pathExtension.lowercased() == "m4a" else { return nil }
        // Voice memos with audio content always exceed 1 KB. Files at or below
        // 1024 bytes are iCloud sync stubs or corrupted transfers.
        guard fileSize > 1024 else { return nil }
        return VoiceMemoEvent(fileURL: url, fileSize: fileSize)
    }
}
