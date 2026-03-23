import Core
import Testing
@testable import Utterd

@Suite("AppleScriptNotesService.noteExists")
struct NotesServiceVerificationTests {
    // MARK: - AC-03.1: Returns true when note exists

    @Test("noteExists returns true when mock returns \"true\"")
    func noteExistsReturnsTrue() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("true")]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "x-coredata://ABC", name: "Work", containerID: nil)

        let exists = try await service.noteExists(title: "X", in: folder)

        #expect(exists == true)
    }

    // MARK: - AC-03.2: Returns false when note does not exist

    @Test("noteExists returns false when mock returns \"false\"")
    func noteExistsReturnsFalse() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("false")]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "x-coredata://ABC", name: "Work", containerID: nil)

        let exists = try await service.noteExists(title: "X", in: folder)

        #expect(exists == false)
    }

    // MARK: - nil folder targets default folder

    @Test("noteExists with nil folder constructs script targeting default folder")
    func noteExistsNilFolderTargetsDefault() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("false")]
        let service = AppleScriptNotesService(executor: mock)

        _ = try await service.noteExists(title: "X", in: nil)

        #expect(mock.executeCalls.count == 1)
        #expect(mock.executeCalls[0].contains("default account"))
    }

    // MARK: - Special characters in title are escaped

    @Test("noteExists escapes special characters in title")
    func noteExistsEscapesTitle() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("false")]
        let service = AppleScriptNotesService(executor: mock)

        _ = try await service.noteExists(title: #"O'Brien's "Notes""#, in: nil)

        let script = mock.executeCalls[0]
        #expect(script.contains(#"O'Brien's \"Notes\""#))
    }
}
