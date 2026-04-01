import Foundation
@testable import Core

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockNotesService: NotesService, @unchecked Sendable {
    // MARK: - listFolders

    nonisolated(unsafe) var listFoldersResult: [NotesFolder] = []
    nonisolated(unsafe) var listFoldersError: Error?
    nonisolated(unsafe) var listFoldersCalls: [NotesFolder?] = []
    /// Keyed by parent folder ID; nil key matches root-level calls (`parent == nil`).
    /// When a key is present its value is returned; otherwise falls back to `listFoldersResult`.
    nonisolated(unsafe) var listFoldersByParent: [String?: [NotesFolder]] = [:]

    func listFolders(in parent: NotesFolder?) async throws -> [NotesFolder] {
        listFoldersCalls.append(parent)
        if let error = listFoldersError {
            throw error
        }
        if let folders = listFoldersByParent[parent?.id] {
            return folders
        }
        return listFoldersResult
    }

    // MARK: - resolveHierarchy

    nonisolated(unsafe) var resolveHierarchyResult: [NotesFolder] = []
    nonisolated(unsafe) var resolveHierarchyError: Error?
    nonisolated(unsafe) var resolveHierarchyCalls: [NotesFolder] = []

    func resolveHierarchy(for folder: NotesFolder) async throws -> [NotesFolder] {
        resolveHierarchyCalls.append(folder)
        if let error = resolveHierarchyError {
            throw error
        }
        return resolveHierarchyResult
    }

    // MARK: - createNote

    nonisolated(unsafe) var createNoteResult: NoteCreationResult = .created
    nonisolated(unsafe) var createNoteError: Error?
    nonisolated(unsafe) var createNoteCalls: [(title: String, body: String, folder: NotesFolder?)] = []

    func createNote(title: String, body: String, in folder: NotesFolder?) async throws -> NoteCreationResult {
        createNoteCalls.append((title: title, body: body, folder: folder))
        if let error = createNoteError {
            throw error
        }
        return createNoteResult
    }

    // MARK: - noteExists

    nonisolated(unsafe) var noteExistsResult: Bool = false
    nonisolated(unsafe) var noteExistsError: Error?
    nonisolated(unsafe) var noteExistsCalls: [(title: String, folder: NotesFolder?)] = []

    func noteExists(title: String, in folder: NotesFolder?) async throws -> Bool {
        noteExistsCalls.append((title: title, folder: folder))
        if let error = noteExistsError {
            throw error
        }
        return noteExistsResult
    }
}
