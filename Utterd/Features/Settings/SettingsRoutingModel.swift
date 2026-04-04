import Core
import Observation

@Observable
@MainActor
final class SettingsRoutingModel {
    var folders: [NotesFolder] = []
    var isLoading = false
    var fetchError: (any Error)?

    private let notesService: any NotesService
    private let settings: UserSettings

    init(notesService: any NotesService, settings: UserSettings) {
        self.notesService = notesService
        self.settings = settings
    }

    func loadFolders() async {
        isLoading = true
        fetchError = nil
        do {
            folders = try await notesService.listFolders(in: nil)
        } catch {
            folders = []
            fetchError = error
        }
        isLoading = false
        validateSelection()
    }

    private func validateSelection() {
        guard let selected = settings.defaultFolderName else { return }
        // Prefer ID-based validation if available, fall back to name
        if let id = settings.defaultFolderID {
            if !folders.contains(where: { $0.id == id }) {
                settings.defaultFolderName = nil
                settings.defaultFolderID = nil
            }
        } else if !folders.map(\.name).contains(selected) {
            settings.defaultFolderName = nil
        }
    }
}
