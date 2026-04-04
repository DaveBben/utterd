import Core
import SwiftUI

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @State private var model: SettingsRoutingModel?

    private let notesService: any NotesService

    init(notesService: any NotesService = AppleScriptNotesService()) {
        self.notesService = notesService
    }

    private var isMacOS26OrLater: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Routing") {
                Picker("Default Folder", selection: Binding(
                    get: { settings.defaultFolderName },
                    set: { newName in
                        settings.defaultFolderName = newName
                        // Store the folder ID alongside the name for reliable resolution
                        if let newName, let folder = model?.folders.first(where: { $0.name == newName }) {
                            settings.defaultFolderID = folder.id
                        } else {
                            settings.defaultFolderID = nil
                        }
                    }
                )) {
                    Text("System Default").tag(String?.none)
                    if let folders = model?.folders, !folders.isEmpty {
                        ForEach(folders, id: \.id) { folder in
                            Text(folder.name).tag(Optional(folder.name))
                        }
                    } else if let name = settings.defaultFolderName {
                        Text(name).tag(Optional(name))
                    }
                }

                if let error = model?.fetchError {
                    HStack {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            if let model {
                                Task { await model.loadFolders() }
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section("LLM") {
                Toggle("Enable Summarization", isOn: $settings.summarizationEnabled)
                    .disabled(!isMacOS26OrLater)

                Toggle("Enable Title Generation", isOn: $settings.titleGenerationEnabled)
                    .disabled(!isMacOS26OrLater)

                if #unavailable(macOS 26) {
                    Text("Requires macOS 26 or later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 300)
        .task {
            let routingModel = SettingsRoutingModel(notesService: notesService, settings: settings)
            model = routingModel
            await routingModel.loadFolders()
        }
    }
}
