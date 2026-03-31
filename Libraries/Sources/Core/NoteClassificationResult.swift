/// The result of classifying a transcript into a Notes folder.
/// A `nil` folder path means the note should go to the default (general) folder.
public struct NoteClassificationResult: Sendable, Equatable {
    public let folderPath: String?
    public let title: String

    public init(folderPath: String?, title: String) {
        self.folderPath = folderPath
        self.title = title
    }
}
