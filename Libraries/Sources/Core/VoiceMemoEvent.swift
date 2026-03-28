import Foundation

/// A detected voice memo that has passed all qualification checks (correct extension,
/// not an iCloud placeholder, above the minimum size threshold). Emitted by
/// ``VoiceMemoWatcher`` to signal that a new memo is ready for pipeline processing.
public struct VoiceMemoEvent: Sendable, Equatable {
    public let fileURL: URL
    public let fileSize: Int64

    public init(fileURL: URL, fileSize: Int64) {
        self.fileURL = fileURL
        self.fileSize = fileSize
    }
}
