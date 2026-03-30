import SwiftUI

@main
struct UtterdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        let _ = { appDelegate.appState = appState }()

        MenuBarExtra("Utterd", systemImage: "waveform", isInserted: Binding(
            get: { appState.permissionResolved },
            set: { appState.permissionResolved = $0 }
        )) {
            MenuBarPopoverView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
