import Foundation

/// A persistent record representing a voice memo in the processing pipeline.
/// Created when a new voice memo is detected; tracks whether the memo has been processed.
public struct MemoRecord: Codable, Sendable, Equatable {
    public let fileURL: URL
    public let dateCreated: Date
    public var dateProcessed: Date?

    public init(fileURL: URL, dateCreated: Date, dateProcessed: Date? = nil) {
        self.fileURL = fileURL
        self.dateCreated = dateCreated
        self.dateProcessed = dateProcessed
    }
}
