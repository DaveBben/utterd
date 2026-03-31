import Core
import Foundation

// MARK: - String escaping

extension String {
    /// Escapes a string for safe interpolation into an AppleScript double-quoted string literal.
    ///
    /// Order matters: backslashes must be escaped before quotes to avoid double-escaping.
    /// Carriage returns (U+000D) are replaced with newlines (U+000A) because AppleScript
    /// string literals cannot contain bare CR characters.
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - ScriptExecutor protocol

/// Abstracts AppleScript execution to allow test injection via `MockScriptExecutor`.
protocol ScriptExecutor: Sendable {
    func execute(script: String) async throws -> String
}

// MARK: - AppleScriptNotesService

/// Concrete ``NotesService`` implementation backed by AppleScript.
struct AppleScriptNotesService: NotesService {
    let executor: any ScriptExecutor

    init(executor: any ScriptExecutor = NSAppleScriptExecutor()) {
        self.executor = executor
    }

    func listFolders(in parent: NotesFolder?) async throws -> [NotesFolder] {
        fatalError("Not yet implemented")
    }

    func resolveHierarchy(for folder: NotesFolder) async throws -> [NotesFolder] {
        fatalError("Not yet implemented")
    }

    func createNote(title: String, body: String, in folder: NotesFolder?) async throws -> NoteCreationResult {
        let escapedTitle = title.appleScriptEscaped
        let escapedBody = body.appleScriptEscaped

        if let folder {
            let folderExists = try await checkFolderExists(id: folder.id)
            if folderExists {
                let script = """
                    tell application "Notes"
                        set targetFolder to folder id "\(folder.id.appleScriptEscaped)"
                        make new note at targetFolder with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
                    end tell
                    """
                _ = try await executor.execute(script: script)
                return .created
            } else {
                try await createNoteInDefaultAccount(title: escapedTitle, body: escapedBody)
                return .createdInDefaultFolder(reason: "Folder no longer exists")
            }
        } else {
            try await createNoteInDefaultAccount(title: escapedTitle, body: escapedBody)
            return .created
        }
    }

    private func checkFolderExists(id: String) async throws -> Bool {
        let script = """
            tell application "Notes"
                try
                    set f to folder id "\(id.appleScriptEscaped)"
                    return "found"
                on error
                    return "not found"
                end try
            end tell
            """
        let result = try await executor.execute(script: script)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) != "not found"
    }

    private func createNoteInDefaultAccount(title: String, body: String) async throws {
        let script = """
            tell application "Notes"
                make new note at default account with properties {name:"\(title)", body:"\(body)"}
            end tell
            """
        _ = try await executor.execute(script: script)
    }

    func noteExists(title: String, in folder: NotesFolder?) async throws -> Bool {
        fatalError("Not yet implemented")
    }
}
