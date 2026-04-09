import AppKit
import Core
import Foundation
import Testing
@testable import Utterd

@Suite("PermissionGate")
struct PermissionGateTests {

    @Test("evaluatePermissionGate returns showPermissionAlert when access is denied")
    @MainActor
    func evaluateGateWhenAccessDenied() {
        let mock = MockFileSystemChecker()
        mock.existsResult = true
        mock.readableResult = false

        let action = evaluatePermissionGate(fileSystem: mock)

        #expect(action == .showPermissionAlert)
    }

    @Test("evaluatePermissionGate returns proceed when access is granted")
    @MainActor
    func evaluateGateWhenAccessGranted() {
        let mock = MockFileSystemChecker()
        mock.existsResult = true
        mock.readableResult = true

        let action = evaluatePermissionGate(fileSystem: mock)

        #expect(action == .proceed)
    }

    @Test("handleOpenSystemSettings calls terminate exactly once when openURL fails")
    @MainActor
    func handleOpenSystemSettingsCallsTerminateOnURLFailure() {
        var terminateCallCount = 0

        handleOpenSystemSettings(
            openURL: { _ in false },
            terminate: { terminateCallCount += 1 }
        )

        #expect(terminateCallCount == 1)
    }

    @Test("handleOpenSystemSettings opens URL containing Privacy_AllFiles")
    @MainActor
    func handleOpenSystemSettingsOpensPrivacyAllFilesURL() {
        var receivedURL: URL?

        handleOpenSystemSettings(
            openURL: { url in receivedURL = url; return true },
            terminate: { }
        )

        #expect(receivedURL?.absoluteString.contains("Privacy_AllFiles") == true)
    }

    @Test("voiceMemoDirectoryURL ends with the expected Voice Memos path component")
    func voiceMemoDirectoryURLPath() {
        #expect(voiceMemoDirectoryURL.path.hasSuffix(
            "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
        ))
    }

    @Test("evaluatePermissionGate returns showDirectoryMissingAlert when directory does not exist")
    @MainActor
    func evaluateGateWhenDirectoryMissing() {
        let mock = MockFileSystemChecker()
        mock.existsResult = false

        let action = evaluatePermissionGate(fileSystem: mock)

        #expect(action == .showDirectoryMissingAlert)
    }

    @Test("evaluatePermissionGate does not call contentsOfDirectory when directory does not exist")
    @MainActor
    func evaluateGateDoesNotListDirectoryWhenMissing() {
        let mock = MockFileSystemChecker()
        mock.existsResult = false

        _ = evaluatePermissionGate(fileSystem: mock)

        #expect(mock.contentsOfDirectoryCallCount == 0)
    }

    @Test("evaluatePermissionGate calls contentsOfDirectory when directory exists")
    @MainActor
    func evaluateGateListsDirectoryWhenPresent() {
        let mock = MockFileSystemChecker()
        mock.existsResult = true
        mock.readableResult = true

        _ = evaluatePermissionGate(fileSystem: mock)

        #expect(mock.contentsOfDirectoryCallCount == 1)
    }

    // MARK: - showDirectoryMissingAlert

    @Test("showDirectoryMissingAlert sets messageText to 'Voice Memos Not Set Up'")
    @MainActor
    func showDirectoryMissingAlertMessageText() {
        var capturedAlert: NSAlert?

        showDirectoryMissingAlert(
            showAlert: { alert in capturedAlert = alert; return .alertFirstButtonReturn },
            terminate: { }
        )

        #expect(capturedAlert?.messageText == "Voice Memos Not Set Up")
    }

    @Test("showDirectoryMissingAlert informativeText mentions Voice Memos and relaunch")
    @MainActor
    func showDirectoryMissingAlertInformativeText() {
        var capturedAlert: NSAlert?

        showDirectoryMissingAlert(
            showAlert: { alert in capturedAlert = alert; return .alertFirstButtonReturn },
            terminate: { }
        )

        let text = capturedAlert?.informativeText ?? ""
        #expect(text.contains("Voice Memos"))
        #expect(text.contains("relaunch"))
    }

    @Test("showDirectoryMissingAlert has a single Quit button")
    @MainActor
    func showDirectoryMissingAlertButtonTitle() {
        var capturedAlert: NSAlert?

        showDirectoryMissingAlert(
            showAlert: { alert in capturedAlert = alert; return .alertFirstButtonReturn },
            terminate: { }
        )

        #expect(capturedAlert?.buttons.count == 1)
        #expect(capturedAlert?.buttons.first?.title == "Quit")
    }

    @Test("showDirectoryMissingAlert calls terminate after the alert is shown")
    @MainActor
    func showDirectoryMissingAlertCallsTerminate() {
        var terminateCallCount = 0

        showDirectoryMissingAlert(
            showAlert: { _ in .alertFirstButtonReturn },
            terminate: { terminateCallCount += 1 }
        )

        #expect(terminateCallCount == 1)
    }
}
