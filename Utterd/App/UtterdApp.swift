import SwiftUI

@main
struct UtterdApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
