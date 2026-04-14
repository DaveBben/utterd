import Foundation

/// Determines whether a file represents a fully-synced voice memo ready for processing.
/// Rules: must be `.m4a` or `.qta`, filename must not start with `.` (iCloud placeholders like
/// `.memo.m4a.icloud`), and size must exceed 1024 bytes (stubs and truncated syncs are smaller).
public enum VoiceMemoQualifier {
    /// File extensions recognized as voice memo formats.
    private static let supportedExtensions: Set<String> = ["m4a", "qta"]

    public static func qualifies(url: URL, fileSize: Int64) -> VoiceMemoEvent? {
        guard rejectionReason(url: url, fileSize: fileSize) == nil else { return nil }
        return VoiceMemoEvent(fileURL: url, fileSize: fileSize)
    }

    /// Returns a human-readable reason why the file was rejected, or nil if it qualifies.
    /// This is the single source of truth for qualification rules.
    public static func rejectionReason(url: URL, fileSize: Int64) -> String? {
        let filename = url.lastPathComponent
        if filename.hasPrefix(".") { return "hidden file (iCloud placeholder)" }
        let ext = url.pathExtension.lowercased()
        if !supportedExtensions.contains(ext) { return "not a supported format (\(ext))" }
        // Voice memos with audio content always exceed 1 KB. Files at or below
        // 1024 bytes are iCloud sync stubs or corrupted transfers.
        if fileSize <= 1024 { return "\(fileSize) bytes below 1024-byte threshold (likely iCloud stub)" }
        return nil
    }
}
