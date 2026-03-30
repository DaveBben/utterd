import Foundation

/// The result of transcribing a voice memo's audio.
public struct TranscriptionResult: Sendable, Equatable {
    public let transcript: String
    public let fileURL: URL

    public init(transcript: String, fileURL: URL) {
        self.transcript = transcript
        self.fileURL = fileURL
    }
}
