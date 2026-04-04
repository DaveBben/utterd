import SwiftUI

@main
struct UtterdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var userSettings = UserSettings()

    var body: some Scene {
        // Wire appState to delegate exactly once, before applicationDidFinishLaunching fires.
        // Assigned in body (not init) because @NSApplicationDelegateAdaptor is not available
        // until after init. The guard prevents repeated assignment on subsequent body evaluations.
        let _ = {
            if appDelegate.appState == nil {
                appDelegate.appState = appState
            }
        }()

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
