import SwiftUI

struct MenuBarMenuContent: View {
    var body: some View {
        Text(MenuBarStrings.title)
        Text(MenuBarStrings.subtitle)

        Divider()

        Button(MenuBarStrings.settingsButton) { }
            .disabled(true)
        Button(MenuBarStrings.quitButton) {
            NSApplication.shared.terminate(nil)
        }
    }
}
