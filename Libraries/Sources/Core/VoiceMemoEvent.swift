import Foundation

/// A detected voice memo that has passed all qualification checks.
public struct VoiceMemoEvent: Sendable, Equatable {
    /// The URL of the voice memo file on disk.
    public let fileURL: URL

    /// The file size in bytes at the time of detection.
    public let fileSize: Int64

    public init(fileURL: URL, fileSize: Int64) {
        self.fileURL = fileURL
        self.fileSize = fileSize
    }
}
