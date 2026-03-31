import Core
import Testing
@testable import Utterd

@Suite("AppleScriptNotesService.listFolders and resolveHierarchy")
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

    // MARK: - resolveHierarchy for top-level folder returns single-element array

    @Test("resolveHierarchy for top-level folder returns single-element array")
    func resolveHierarchyTopLevel() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("rootId\tFinance\t\n")]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "rootId", name: "Finance", containerID: nil)

        let hierarchy = try await service.resolveHierarchy(for: folder)

        #expect(hierarchy.count == 1)
        #expect(hierarchy[0].id == "rootId")
    }

    // MARK: - AC-01.3: resolveHierarchy for nested folder returns root-to-leaf order

    @Test("resolveHierarchy for nested folder returns root-to-leaf order")
    func resolveHierarchyNested() async throws {
        let mock = MockScriptExecutor()
        mock.executeResults = [.success("parentId\tFinance\t\nchildId\tTaxes\tparentId\n")]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "childId", name: "Taxes", containerID: "parentId")

        let hierarchy = try await service.resolveHierarchy(for: folder)

        #expect(hierarchy.count == 2)
        #expect(hierarchy[0].id == "parentId")
        #expect(hierarchy[0].name == "Finance")
        #expect(hierarchy[1].id == "childId")
        #expect(hierarchy[1].name == "Taxes")
    }

    // MARK: - resolveHierarchy for deeply nested folder (3 levels) returns correct path

    @Test("resolveHierarchy for deeply nested folder returns full root-to-leaf path")
    func resolveHierarchyDeep() async throws {
        let mock = MockScriptExecutor()
        let bulkOutput = "rootId\tRoot\t\nmidId\tMid\trootId\nleafId\tLeaf\tmidId\n"
        mock.executeResults = [.success(bulkOutput)]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "leafId", name: "Leaf", containerID: "midId")

        let hierarchy = try await service.resolveHierarchy(for: folder)

        #expect(hierarchy.count == 3)
        #expect(hierarchy[0].id == "rootId")
        #expect(hierarchy[1].id == "midId")
        #expect(hierarchy[2].id == "leafId")
    }

    // MARK: - resolveHierarchy stops at unknown containerID (account root)

    @Test("resolveHierarchy stops walking when containerID is not a folder (e.g. account)")
    func resolveHierarchyUnknownContainerStopsAtRoot() async throws {
        let mock = MockScriptExecutor()
        // Bulk output only has the child — containerID "accountId" is the account, not a folder
        mock.executeResults = [.success("childId\tTaxes\taccountId\n")]
        let service = AppleScriptNotesService(executor: mock)
        let folder = NotesFolder(id: "childId", name: "Taxes", containerID: "accountId")

        let hierarchy = try await service.resolveHierarchy(for: folder)
        // Walk stops at the unrecognized containerID — folder is treated as a root
        #expect(hierarchy.count == 1)
        #expect(hierarchy[0].id == "childId")
    }
}
