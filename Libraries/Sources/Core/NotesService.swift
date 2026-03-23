import Foundation

/// Errors thrown by ``NotesService`` implementations.
public enum NotesServiceError: Error, Sendable {
    case notesNotAccessible(String)
    case automationPermissionDenied
    case folderNotFound(String)
    case scriptExecutionFailed(String)
}

/// Abstracts Apple Notes operations so tests can inject a mock.
///
/// - ``listFolders(in:)`` discovers the user's folder structure.
/// - ``createNote(title:body:in:)`` creates a note, with fallback.
/// - ``noteExists(title:in:)`` verifies a note exists — test support only.
public protocol NotesService: Sendable {
    /// Returns the immediate child folders of `parent`, or top-level folders when `parent` is `nil`.
    func listFolders(in parent: NotesFolder?) async throws -> [NotesFolder]

    /// Creates a note in `folder`, or the default folder when `folder` is `nil`.
    /// Returns `.createdInDefaultFolder` if the specified folder no longer exists.
    func createNote(title: String, body: String, in folder: NotesFolder?) async throws -> NoteCreationResult

    /// Checks whether a note with `title` exists in `folder` (or the default folder when `nil`).
    /// Intended for integration test verification only.
    func noteExists(title: String, in folder: NotesFolder?) async throws -> Bool
}
