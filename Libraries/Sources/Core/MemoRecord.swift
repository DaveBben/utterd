import Foundation

/// A persistent record representing a voice memo in the processing pipeline.
/// Created when a new voice memo is detected; tracks the memo's lifecycle state:
/// unprocessed, successfully processed, or permanently failed.
public struct MemoRecord: Codable, Sendable, Equatable {
    public let fileURL: URL
    public let dateCreated: Date
    public var dateProcessed: Date?
    public var dateFailed: Date?
    public var failureReason: String?

    public init(fileURL: URL, dateCreated: Date, dateProcessed: Date? = nil, dateFailed: Date? = nil, failureReason: String? = nil) {
        self.fileURL = fileURL
        self.dateCreated = dateCreated
        self.dateProcessed = dateProcessed
        self.dateFailed = dateFailed
        self.failureReason = failureReason
    }
}
