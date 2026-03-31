import Core
import Foundation
import Testing
@testable import Utterd

// Integration tests that exercise the real AppleScriptNotesService against live Apple Notes.
// All tests are guarded by requireNotesAccess() and skipped gracefully when Notes is not available.
// All test notes use UTTERD_TEST_{uuid} prefixed titles for identification and cleanup.

@Suite("AppleScriptNotesService Integration")
struct AppleScriptNotesServiceIntegrationTests {
    let service = AppleScriptNotesService(executor: NSAppleScriptExecutor())

    // Verify Notes is accessible before any test in this suite.
    // If Notes is not accessible, #require throws a RequirementFailure, stopping the test
    // with a clear message rather than a cryptic assertion failure from the real operation.
    private func requireNotesAccess() async throws {
        let executor = NSAppleScriptExecutor()
        let script = #"tell application "Notes" to name of default account"#
        let accessible: Bool
        do {
            _ = try await executor.execute(script: script)
            accessible = true
        } catch {
            accessible = false
        }
        try #require(
            accessible,
            "Apple Notes is not accessible — grant Automation permission or run on a system with Notes."
        )
    }

    // Deletes all notes with titles starting with UTTERD_TEST_ from previous failed runs.
    private func cleanupOrphanedTestNotes() async {
        let script = """
            tell application "Notes"
                set notesToDelete to {}
                repeat with n in notes of default account
                    if name of n starts with "UTTERD_TEST_" then
                        set end of notesToDelete to n
                    end if
                end repeat
                repeat with n in notesToDelete
                    delete n
                end repeat
            end tell
            """
        _ = try? await service.executor.execute(script: script)
    }

    // Deletes a specific note by title from the default account.
    private func deleteTestNote(title: String) async {
        let escapedTitle = title.appleScriptEscaped
        let script = """
            tell application "Notes"
                set notesToDelete to {}
                repeat with n in notes of default account
                    if name of n is "\(escapedTitle)" then
                        set end of notesToDelete to n
                    end if
                end repeat
                repeat with n in notesToDelete
                    delete n
                end repeat
            end tell
            """
        _ = try? await service.executor.execute(script: script)
    }

    // MARK: - AC-02.2, AC-03.1: Create in default folder, verify existence

    @Test("createNote in default folder returns .created and noteExists confirms it")
    func createNoteInDefaultFolderAndVerify() async throws {
        try await requireNotesAccess()
        await cleanupOrphanedTestNotes()

        let title = "UTTERD_TEST_\(UUID().uuidString)"
        defer { Task { await deleteTestNote(title: title) } }

        let result = try await service.createNote(title: title, body: "Integration test body", in: nil)

        #expect(result == .created)

        let exists = try await service.noteExists(title: title, in: nil)
        #expect(exists == true)
    }

    // MARK: - Edge case: empty body

    @Test("createNote with empty body succeeds")
    func createNoteWithEmptyBody() async throws {
        try await requireNotesAccess()
        await cleanupOrphanedTestNotes()

        let title = "UTTERD_TEST_\(UUID().uuidString)"
        defer { Task { await deleteTestNote(title: title) } }

        let result = try await service.createNote(title: title, body: "", in: nil)

        #expect(result == .created)
    }

    // MARK: - Edge case: special characters in title and body

    @Test("createNote with special characters succeeds and noteExists finds it")
    func createNoteWithSpecialCharacters() async throws {
        try await requireNotesAccess()
        await cleanupOrphanedTestNotes()

        // Title uses apostrophe (common special char); body uses backslash and quotes.
        // The UUID ensures uniqueness; UTTERD_TEST_ prefix ensures cleanup sweep catches it.
        let title = "UTTERD_TEST_\(UUID().uuidString)_O'Brien"
        let body = "Path: C:\\Users\\test\nLine 2 with \"quotes\""
        defer { Task { await deleteTestNote(title: title) } }

        let result = try await service.createNote(title: title, body: body, in: nil)

        #expect(result == .created)

        let exists = try await service.noteExists(title: title, in: nil)
        #expect(exists == true)
    }

    // MARK: - AC-03.2: noteExists returns false for never-created title

    @Test("noteExists returns false for a UUID title never created")
    func noteExistsReturnsFalseForUnknownTitle() async throws {
        try await requireNotesAccess()

        let title = "UTTERD_TEST_\(UUID().uuidString)_NONEXISTENT"

        let exists = try await service.noteExists(title: title, in: nil)

        #expect(exists == false)
    }

    // MARK: - AC-02.4: Notes auto-launches when not running

    @Test("createNote succeeds regardless of Notes app state (Notes auto-launches)")
    func createNoteNotesAutoLaunches() async throws {
        try await requireNotesAccess()
        await cleanupOrphanedTestNotes()

        // We cannot reliably quit Notes in a test environment without side effects,
        // but we can verify that the note creation succeeds unconditionally — the
        // tell-application block in AppleScript launches Notes if it is not running.
        let title = "UTTERD_TEST_\(UUID().uuidString)"
        defer { Task { await deleteTestNote(title: title) } }

        let result = try await service.createNote(title: title, body: "Auto-launch test", in: nil)

        #expect(result == .created)
    }
}
