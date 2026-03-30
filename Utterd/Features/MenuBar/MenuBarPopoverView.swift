import SwiftUI

struct MenuBarPopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MenuBarStrings.title)
                .font(.headline)
            Text(MenuBarStrings.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            Button(MenuBarStrings.settingsButton) { }
            Button(MenuBarStrings.quitButton) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}
