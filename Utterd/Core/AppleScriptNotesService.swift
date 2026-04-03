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
        let script: String
        if let parent {
            script = """
                tell application "Notes"
                    set output to ""
                    set targetFolder to folder id "\(parent.id.appleScriptEscaped)"
                    repeat with f in folders of targetFolder
                        set fid to id of f
                        set fname to name of f
                        set cid to id of container of f
                        set output to output & fid & tab & fname & tab & cid & linefeed
                    end repeat
                    return output
                end tell
                """
        } else {
            script = """
                tell application "Notes"
                    set output to ""
                    repeat with f in folders of default account
                        set fid to id of f
                        set fname to name of f
                        set output to output & fid & tab & fname & tab & linefeed
                    end repeat
                    return output
                end tell
                """
        }

        let raw: String
        do {
            raw = try await executor.execute(script: script)
        } catch NotesServiceError.automationPermissionDenied {
            throw NotesServiceError.automationPermissionDenied
        } catch {
            throw NotesServiceError.notesNotAccessible(error.localizedDescription)
        }

        return parseFolderLines(raw)
    }

    // Parses tab-delimited folder output: each line is "id\tname\tcontainerID\n".
    // containerID field may be empty (top-level folders).
    private func parseFolderLines(_ raw: String) -> [NotesFolder] {
        raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> NotesFolder? in
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 3 else { return nil }
                let id = fields[0]
                let name = fields[1]
                let containerID = fields[2].isEmpty ? nil : fields[2]
                guard !id.isEmpty else { return nil }
                return NotesFolder(id: id, name: name, containerID: containerID)
            }
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
                do {
                    _ = try await executor.execute(script: script)
                } catch NotesServiceError.automationPermissionDenied {
                    throw NotesServiceError.automationPermissionDenied
                } catch {
                    throw NotesServiceError.notesNotAccessible(error.localizedDescription)
                }
                return .created
            } else {
                try await createNoteInDefaultAccount(escapedTitle: escapedTitle, escapedBody: escapedBody)
                return .createdInDefaultFolder(reason: "Folder no longer exists")
            }
        } else {
            try await createNoteInDefaultAccount(escapedTitle: escapedTitle, escapedBody: escapedBody)
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
        let result: String
        do {
            result = try await executor.execute(script: script)
        } catch NotesServiceError.automationPermissionDenied {
            throw NotesServiceError.automationPermissionDenied
        } catch {
            throw NotesServiceError.notesNotAccessible(error.localizedDescription)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "found"
    }

    private func createNoteInDefaultAccount(escapedTitle: String, escapedBody: String) async throws {
        let script = """
            tell application "Notes"
                make new note at default account with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
            end tell
            """
        do {
            _ = try await executor.execute(script: script)
        } catch NotesServiceError.automationPermissionDenied {
            throw NotesServiceError.automationPermissionDenied
        } catch {
            throw NotesServiceError.notesNotAccessible(error.localizedDescription)
        }
    }

    func noteExists(title: String, in folder: NotesFolder?) async throws -> Bool {
        let escapedTitle = title.appleScriptEscaped
        let script: String
        if let folder {
            script = """
                tell application "Notes"
                    tell folder id "\(folder.id.appleScriptEscaped)"
                        return (name of notes) contains "\(escapedTitle)"
                    end tell
                end tell
                """
        } else {
            script = """
                tell application "Notes"
                    tell default account
                        return (name of notes) contains "\(escapedTitle)"
                    end tell
                end tell
                """
        }
        let result: String
        do {
            result = try await executor.execute(script: script)
        } catch NotesServiceError.automationPermissionDenied {
            throw NotesServiceError.automationPermissionDenied
        } catch {
            throw NotesServiceError.notesNotAccessible(error.localizedDescription)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
}
