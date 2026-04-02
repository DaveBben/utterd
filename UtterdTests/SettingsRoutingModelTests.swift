import Foundation
import Testing
import Core
@testable import Utterd

// MARK: - Mock

final class MockNotesServiceForSettings: NotesService, @unchecked Sendable {
    nonisolated(unsafe) var listFoldersResult: [NotesFolder] = []
    nonisolated(unsafe) var listFoldersError: Error?

    func listFolders(in parent: NotesFolder?) async throws -> [NotesFolder] {
        if let error = listFoldersError { throw error }
        return listFoldersResult
    }

    func resolveHierarchy(for folder: NotesFolder) async throws -> [NotesFolder] { fatalError() }
    func createNote(title: String, body: String, in folder: NotesFolder?) async throws -> NoteCreationResult { fatalError() }
    func noteExists(title: String, in folder: NotesFolder?) async throws -> Bool { fatalError() }
}

// MARK: - Tests

@Suite("SettingsRoutingModel")
struct SettingsRoutingModelTests {

    @MainActor
    private func makeSettings() -> UserSettings {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserSettings(defaults: defaults)
    }

    @Test("loadFolders success populates folders and clears loading and error")
    @MainActor
    func loadFoldersSuccess() async {
        let service = MockNotesServiceForSettings()
        service.listFoldersResult = [
            NotesFolder(id: "1", name: "Work"),
            NotesFolder(id: "2", name: "Personal"),
        ]
        let settings = makeSettings()
        let model = SettingsRoutingModel(notesService: service, settings: settings)

        await model.loadFolders()

        #expect(model.folders.count == 2)
        #expect(model.folders[0].name == "Work")
        #expect(model.folders[1].name == "Personal")
        #expect(model.isLoading == false)
        #expect(model.fetchError == nil)
    }

    @Test("loadFolders failure sets fetchError, clears folders and loading")
    @MainActor
    func loadFoldersFailure() async {
        let service = MockNotesServiceForSettings()
        service.listFoldersError = NotesServiceError.automationPermissionDenied
        let settings = makeSettings()
        let model = SettingsRoutingModel(notesService: service, settings: settings)

        await model.loadFolders()

        #expect(model.folders.isEmpty)
        #expect(model.fetchError != nil)
        #expect(model.isLoading == false)
    }

    @Test("validateSelection keeps selection when folder name is in list")
    @MainActor
    func validateSelectionMatchingFolder() async {
        let service = MockNotesServiceForSettings()
        service.listFoldersResult = [NotesFolder(id: "1", name: "Work")]
        let settings = makeSettings()
        settings.defaultFolderName = "Work"
        let model = SettingsRoutingModel(notesService: service, settings: settings)

        await model.loadFolders()

        #expect(settings.defaultFolderName == "Work")
    }

    @Test("validateSelection resets selection when folder name is not in list")
    @MainActor
    func validateSelectionStaleFolder() async {
        let service = MockNotesServiceForSettings()
        service.listFoldersResult = [NotesFolder(id: "1", name: "Work")]
        let settings = makeSettings()
        settings.defaultFolderName = "DeletedFolder"
        let model = SettingsRoutingModel(notesService: service, settings: settings)

        await model.loadFolders()

        #expect(settings.defaultFolderName == nil)
    }
}
