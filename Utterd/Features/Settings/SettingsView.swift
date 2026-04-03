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

            Section("LLM") {
                Toggle("Enable LLM Routing", isOn: $settings.llmEnabled)
                    .disabled(!isMacOS26OrLater)

                if #unavailable(macOS 26) {
                    Text("Requires macOS 26 or later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.llmEnabled {
                    Picker("Routing Mode", selection: $settings.useCustomPrompt) {
                        Text("Auto-route").tag(false)
                        Text("Custom prompt").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if settings.useCustomPrompt {
                        TextEditor(text: $settings.customPrompt)
                            .frame(minHeight: 150)
                            .font(.body.monospaced())

                        Button("Reset to Default") {
                            settings.customPrompt = TranscriptClassifier.defaultCustomPrompt
                        }
                    }

                    Toggle("Enable Summarization", isOn: $settings.summarizationEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: settings.llmEnabled && settings.useCustomPrompt ? 520 : 300)
        .task {
            let routingModel = SettingsRoutingModel(notesService: notesService, settings: settings)
            model = routingModel
            await routingModel.loadFolders()
        }
    }
}
