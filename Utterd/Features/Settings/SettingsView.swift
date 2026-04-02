import Core
import SwiftUI

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @State private var model: SettingsRoutingModel?

    private let notesService: any NotesService

    init(notesService: any NotesService = AppleScriptNotesService()) {
        self.notesService = notesService
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Routing") {
                Picker("Default Folder", selection: $settings.defaultFolderName) {
                    Text("System Default").tag(String?.none)
                    ForEach(model?.folders ?? [], id: \.id) { folder in
                        Text(folder.name).tag(Optional(folder.name))
                    }
                }

                if let error = model?.fetchError {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // MARK: - LLM Section (Task 5)
        }
        .task {
            let routingModel = SettingsRoutingModel(notesService: notesService, settings: settings)
            model = routingModel
            await routingModel.loadFolders()
        }
    }
}
