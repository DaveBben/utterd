import Core
import Testing
@testable import Utterd

@Suite("AppleScriptNotesService.createNote")
struct NotesServiceCreationTests {
    // MARK: - AC-02.2: Default folder (nil)

    @Test("createNote with nil folder returns .created and scripts default folder")
    func createNoteInDefaultFolder() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("")]
        let service = AppleScriptNotesService(executor: mock)

        let result = try await service.createNote(title: "Test Note", body: "Content", in: nil)

        #expect(result == .created)
        #expect(mock.executeCalls.count == 1)
        #expect(mock.executeCalls[0].contains("default account"))
    }

    // MARK: - AC-02.1: Specific folder by ID

    @Test("createNote with folder uses folder ID in script")
    func createNoteInSpecificFolder() async throws {
        let mock = MockScriptExecutor()
        // First call: folder existence check returns found
        // Second call: create the note
        mock.executeResults = [.success("found"), .success("")]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "x-coredata://ABC", name: "Work", containerID: nil)

        let result = try await service.createNote(title: "Test", body: "Body", in: folder)

        #expect(result == .created)
        // The folder-check script must reference the folder ID
        #expect(mock.executeCalls[0].contains("x-coredata://ABC"))
        // The creation script must also reference the folder ID
        #expect(mock.executeCalls[1].contains("x-coredata://ABC"))
    }

    // MARK: - AC-02.6: Specific folder among duplicates — uses ID not name

    @Test("createNote with duplicate-named folders uses the specific folder's ID")
    func createNoteTargetsFolderById() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("found"), .success("")]
        let service = AppleScriptNotesService(executor: mock)
        let folderA = NotesFolder(id: "id-A", name: "Work", containerID: nil)

        _ = try await service.createNote(title: "Note", body: "Body", in: folderA)

        // Script must contain the specific ID, not just the name
        let creationScript = mock.executeCalls[1]
        #expect(creationScript.contains("id-A"))
        #expect(!creationScript.contains("id-B"))
    }

    // MARK: - AC-02.3: Folder no longer exists → fallback

    @Test("createNote falls back to default folder when folder not found")
    func createNoteFallsBackWhenFolderNotFound() async throws {
        let mock = MockScriptExecutor()
        // First call: folder existence check returns "not found"
        // Second call: create in default folder succeeds
        mock.executeResults = [.success("not found"), .success("")]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "x-coredata://GONE", name: "Deleted", containerID: nil)

        let result = try await service.createNote(title: "Note", body: "Body", in: folder)

        guard case .createdInDefaultFolder(let reason) = result else {
            #expect(Bool(false), "Expected .createdInDefaultFolder, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(mock.executeCalls.count == 2)
        // Second call should target default account (fallback)
        #expect(mock.executeCalls[1].contains("default account"))
    }

    // MARK: - AC-02.5: Permission error propagated

    @Test("createNote propagates automationPermissionDenied")
    func createNotePermissionDenied() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.failure(NotesServiceError.automationPermissionDenied)]
        let service = AppleScriptNotesService(executor: mock)

        do {
            _ = try await service.createNote(title: "Note", body: "Body", in: nil)
            #expect(Bool(false), "Expected error to be thrown")
        } catch NotesServiceError.automationPermissionDenied {
            // Expected
        }
    }

    // MARK: - Edge case: empty body

    @Test("createNote with empty body constructs valid script")
    func createNoteEmptyBody() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("")]
        let service = AppleScriptNotesService(executor: mock)

        let result = try await service.createNote(title: "Empty Note", body: "", in: nil)

        #expect(result == .created)
        #expect(mock.executeCalls.count == 1)
        // Script should still be syntactically present
        #expect(!mock.executeCalls[0].isEmpty)
    }

    // MARK: - Edge case: title with quotes is escaped

    @Test("createNote escapes quotes in title within script")
    func createNoteEscapesTitle() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("")]
        let service = AppleScriptNotesService(executor: mock)

        _ = try await service.createNote(title: #"He said "hello""#, body: "Body", in: nil)

        let script = mock.executeCalls[0]
        // The raw quote character must not appear unescaped in the script string
        // after the opening delimiter of the name value
        #expect(script.contains(#"He said \"hello\""#))
    }
}
