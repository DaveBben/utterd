import SwiftUI

@main
struct UtterdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        // Wire appState to the delegate so applicationDidFinishLaunching can set permissionResolved.
        // Uses an inline closure because @State and @NSApplicationDelegateAdaptor are both SwiftUI-managed.
        // Runs during body evaluation, before the delegate lifecycle method fires.
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
