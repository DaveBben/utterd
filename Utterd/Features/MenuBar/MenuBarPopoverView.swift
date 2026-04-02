import SwiftUI

struct MenuBarMenuContent: View {
    var body: some View {
        Text(MenuBarStrings.title)

        Divider()

        Button(MenuBarStrings.quitButton) {
            NSApplication.shared.terminate(nil)
        }
    }
}
