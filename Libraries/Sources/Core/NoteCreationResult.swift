/// The outcome of a note creation request.
/// `.createdInDefaultFolder` signals that the requested folder was unavailable
/// and the note was placed in the default folder instead.
public enum NoteCreationResult: Sendable, Equatable {
    case created
    case createdInDefaultFolder(reason: String)

    public static func == (lhs: NoteCreationResult, rhs: NoteCreationResult) -> Bool {
        switch (lhs, rhs) {
        case (.created, .created):
            return true
        case (.createdInDefaultFolder(let l), .createdInDefaultFolder(let r)):
            return l == r
        default:
            return false
        }
    }
}
