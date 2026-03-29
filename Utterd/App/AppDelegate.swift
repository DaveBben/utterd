import AppKit
import Core

enum PermissionGateAction {
    case proceed
    case showPermissionAlert
}

@MainActor
func evaluatePermissionGate(checker: PermissionChecker) -> PermissionGateAction {
    checker.checkAccess()
    return checker.hasVoiceMemoAccess ? .proceed : .showPermissionAlert
}

@MainActor
func handleOpenSystemSettings(
    openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) },
    terminate: () -> Void = { NSApplication.shared.terminate(nil) }
) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
        _ = openURL(url)
    }
    terminate()
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var permissionChecker = PermissionChecker(fileSystem: RealFileSystemChecker())

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip permission gate during unit tests to prevent alert from blocking test runner.
        // Works with xcodebuild. Does not detect swift test CLI.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        let action = evaluatePermissionGate(checker: permissionChecker)
        if action == .showPermissionAlert {
            showPermissionAlert()
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = "Utterd needs to read voice memos from iCloud. Please grant Full Disk Access in System Settings > Privacy & Security > Full Disk Access, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        let quitButton = alert.addButton(withTitle: "Quit")
        quitButton.keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            handleOpenSystemSettings()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
}
