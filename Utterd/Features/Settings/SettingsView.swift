import AppKit
import Core
import os
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    // 300 words stays well within the 3000-word context budget after system prompt overhead (~200 words)
    private static let maxInstructionWords = 300

    @Environment(UserSettings.self) private var settings
    @State private var model: SettingsRoutingModel?

    private let notesService: any NotesService
    private let logger = Logger(subsystem: "com.bennett.Utterd", category: "Settings")

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
                    get: {
                        if model?.folders.isEmpty == false {
                            // Folders loaded — use ID to match ForEach tags
                            return settings.defaultFolderID
                        }
                        // Still loading — return name to match placeholder tag
                        return settings.defaultFolderName
                    },
                    set: { newValue in
                        if let newValue, let folder = model?.folders.first(where: { $0.id == newValue }) {
                            settings.defaultFolderID = folder.id
                            settings.defaultFolderName = folder.name
                        } else {
                            settings.defaultFolderID = nil
                            settings.defaultFolderName = nil
                        }
                    }
                )) {
                    Text("Notes (default)").tag(String?.none)
                    if let folders = model?.folders, !folders.isEmpty {
                        ForEach(folders, id: \.id) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    } else if let name = settings.defaultFolderName {
                        // Folders not yet loaded — show stored name as placeholder
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

                if settings.summarizationEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Summarization Instructions")
                            .font(.headline)
                        Text("Guide how memos are summarized (optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Hard-truncate at word limit on each keystroke.
                        // The word counter below provides visual feedback.
                        TextEditor(text: Binding(
                            get: { settings.summarizationInstructions ?? "" },
                            set: { newValue in
                                let enforced = truncateToWordLimit(newValue, limit: Self.maxInstructionWords)
                                settings.summarizationInstructions = enforced.isEmpty ? nil : enforced
                            }
                        ))
                        .frame(height: 80)
                        .font(.body)
                        Text("\(wordCount(settings.summarizationInstructions ?? "")) / \(Self.maxInstructionWords) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Enable Title Generation", isOn: $settings.titleGenerationEnabled)
                    .disabled(!isMacOS26OrLater)

                if #unavailable(macOS 26) {
                    Text("Requires macOS 26 or later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        let currentlyEnabled = SMAppService.mainApp.status == .enabled
                        guard newValue != currentlyEnabled else { return }
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            logger.error("Failed to \(newValue ? "register" : "unregister") login item: \(error)")
                            settings.launchAtLogin = currentlyEnabled
                        }
                    }
            }
            .onAppear {
                settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
                Button("Open Log File") {
                    let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Utterd/utterd.log")
                    if FileManager.default.fileExists(atPath: logURL.path) {
                        NSWorkspace.shared.open(logURL)
                    } else {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logURL.deletingLastPathComponent().path)
                    }
                }
                Link("View Releases on GitHub", destination: URL(string: "https://github.com/DaveBben/utterd/releases")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .task {
            let routingModel = SettingsRoutingModel(notesService: notesService, settings: settings)
            model = routingModel
            await routingModel.loadFolders()
        }
    }
}
