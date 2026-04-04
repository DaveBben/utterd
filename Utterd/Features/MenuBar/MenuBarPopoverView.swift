import SwiftUI

struct MenuBarMenuContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(MenuBarStrings.lastSyncTitle)
            .disabled(true)

        if let date = appState.lastProcessedDate {
            Text(date, format: .dateTime.month().day().hour().minute())
                .disabled(true)
        } else {
            Text(MenuBarStrings.noMemosProcessed)
                .disabled(true)
        }

        Divider()

        Button(MenuBarStrings.settingsButton) {
            // NSApp.activate() is required for menu-bar-only apps — without it,
            // the Settings window won't reappear after being closed.
            NSApp.activate()
            openSettings()
        }

        Divider()

        Button(MenuBarStrings.quitButton) {
            NSApplication.shared.terminate(nil)
        }
    }
}
