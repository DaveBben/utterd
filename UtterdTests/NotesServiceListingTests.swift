import Core
import Testing
@testable import Utterd

@Suite("AppleScriptNotesService.listFolders")
struct NotesServiceListingTests {
    // MARK: - AC-01.1: listFolders(in: nil) parses top-level folders

    @Test("listFolders(in: nil) parses tab-delimited output into NotesFolder structs")
    func listFoldersTopLevel() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("id1\tFinance\t\nid2\tPersonal\t\n")]
        let service = AppleScriptNotesService(executor: mock)

        let folders = try await service.listFolders(in: nil)

        #expect(folders.count == 2)
        #expect(folders[0].id == "id1")
        #expect(folders[0].name == "Finance")
        #expect(folders[0].containerID == nil)
        #expect(folders[1].id == "id2")
        #expect(folders[1].name == "Personal")
        #expect(folders[1].containerID == nil)
    }

    // MARK: - AC-01.2: listFolders(in: parent) constructs script referencing parent ID

    @Test("listFolders(in: parent) constructs script referencing parent folder ID")
    func listFoldersWithParent() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("childId\tTaxes\tparentId\n")]
        let service = AppleScriptNotesService(executor: mock)
        let parent = NotesFolder(id: "parentId", name: "Finance", containerID: nil)

        let folders = try await service.listFolders(in: parent)

        #expect(mock.executeCalls.count == 1)
        #expect(mock.executeCalls[0].contains("parentId"))
        #expect(folders.count == 1)
        #expect(folders[0].id == "childId")
        #expect(folders[0].name == "Taxes")
        #expect(folders[0].containerID == "parentId")
    }

    // MARK: - AC-01.4: listFolders with empty output returns empty array

    @Test("listFolders with empty mock output returns empty array")
    func listFoldersEmpty() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("")]
        let service = AppleScriptNotesService(executor: mock)

        let folders = try await service.listFolders(in: nil)

        #expect(folders.isEmpty)
    }

    // MARK: - AC-01.5: listFolders wraps non-permission errors as notesNotAccessible

    @Test("listFolders wraps generic executor error as notesNotAccessible")
    func listFoldersWrapsGenericError() async throws {
        let mock = MockScriptExecutor()
        struct SomeError: Error {}
        mock.executeResults = [.failure(SomeError())]
        let service = AppleScriptNotesService(executor: mock)

        do {
            _ = try await service.listFolders(in: nil)
            Issue.record("Expected notesNotAccessible to be thrown")
        } catch let error as NotesServiceError {
            if case .notesNotAccessible = error {
                // expected — generic errors wrapped as notesNotAccessible (AC-01.5)
            } else {
                Issue.record("Expected notesNotAccessible, got \(error)")
            }
        } catch {
            Issue.record("Expected NotesServiceError, got \(error)")
        }
    }

    // MARK: - AC-01.6: listFolders propagates automationPermissionDenied

    @Test("listFolders propagates automationPermissionDenied error")
    func listFoldersPropagatesPermissionDenied() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.failure(NotesServiceError.automationPermissionDenied)]
        let service = AppleScriptNotesService(executor: mock)

        do {
            _ = try await service.listFolders(in: nil)
            Issue.record("Expected automationPermissionDenied to be thrown")
        } catch NotesServiceError.automationPermissionDenied {
            // expected — permission error passes through unwrapped
        } catch {
            Issue.record("Expected automationPermissionDenied, got \(error)")
        }
    }

}
