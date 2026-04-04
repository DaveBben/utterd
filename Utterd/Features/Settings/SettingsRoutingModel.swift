import Core
import Observation

@Observable
@MainActor
final class SettingsRoutingModel {
    var folders: [NotesFolder] = []
    var fetchError: (any Error)?

    private let notesService: any NotesService
    private let settings: UserSettings

    init(notesService: any NotesService, settings: UserSettings) {
        self.notesService = notesService
        self.settings = settings
    }

    func loadFolders() async {
        fetchError = nil
        do {
            let loaded = try await notesService.listFolders(in: nil)
            // Validate and backfill the ID *before* publishing the folder list,
            // so the picker sees consistent tags and selection in a single render pass.
            validateSelection(against: loaded)
            folders = loaded
        } catch {
            folders = []
            fetchError = error
        }
    }

    private func validateSelection(against folders: [NotesFolder]) {
        guard settings.defaultFolderName != nil else { return }
        guard !folders.isEmpty else { return }
        if let id = settings.defaultFolderID {
            if let match = folders.first(where: { $0.id == id }) {
                settings.defaultFolderName = match.name
            } else {
                settings.defaultFolderName = nil
                settings.defaultFolderID = nil
            }
        } else if let match = folders.first(where: { $0.name == settings.defaultFolderName }) {
            settings.defaultFolderID = match.id
        } else {
            settings.defaultFolderName = nil
        }
    }
}
