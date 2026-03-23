/// The outcome of a note creation request.
/// `.createdInDefaultFolder` signals that the requested folder was unavailable
/// and the note was placed in the default folder instead.
public enum NoteCreationResult: Sendable, Equatable {
    case created
    case createdInDefaultFolder(reason: String)
}
