import SwiftUI

@main
struct UtterdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var userSettings = UserSettings()

    var body: some Scene {
        // Wire appState to delegate before applicationDidFinishLaunching fires.
        let _ = { appDelegate.appState = appState }()

        MenuBarExtra("Utterd", systemImage: "waveform", isInserted: Binding(
            get: { appState.permissionResolved },
            set: { appState.permissionResolved = $0 }
        )) {
            MenuBarMenuContent()
                .environment(appState)
        }

        Settings {
            SettingsView()
                .environment(userSettings)
        }
    }
}
