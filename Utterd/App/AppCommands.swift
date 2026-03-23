import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // Replace the default New Item command
        CommandGroup(replacing: .newItem) {}

        // App-specific commands
        CommandMenu("Utterd") {
            Button("Refresh") {
                // TODO: Implement refresh action
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
