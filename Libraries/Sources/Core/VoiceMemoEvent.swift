import Foundation

public struct VoiceMemoEvent: Sendable, Equatable {
    public let fileURL: URL
    public let fileSize: Int64

    public init(fileURL: URL, fileSize: Int64) {
        self.fileURL = fileURL
        self.fileSize = fileSize
    }
}
