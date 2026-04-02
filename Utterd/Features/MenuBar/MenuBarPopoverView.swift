import SwiftUI

struct MenuBarMenuContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Text(MenuBarStrings.lastSyncTitle)
            .disabled(true)

        if let date = appState.lastProcessedDate {
            Text(date, style: .relative)
                .disabled(true)
        } else {
            Text(MenuBarStrings.noMemosProcessed)
                .disabled(true)
        }

        Divider()

        Button(MenuBarStrings.quitButton) {
            NSApplication.shared.terminate(nil)
        }
    }
}
