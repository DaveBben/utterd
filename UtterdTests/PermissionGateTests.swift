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
        mock.readableResult = false

        let action = evaluatePermissionGate(fileSystem: mock)

        #expect(action == .showPermissionAlert)
    }

    @Test("evaluatePermissionGate returns proceed when access is granted")
    @MainActor
    func evaluateGateWhenAccessGranted() {
        let mock = MockFileSystemChecker()
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
        mock.directoryExistsResult = false

        let action = evaluatePermissionGate(fileSystem: mock)

        #expect(action == .showDirectoryMissingAlert)
    }

    @Test("evaluatePermissionGate does not call contentsOfDirectory when directory does not exist")
    @MainActor
    func evaluateGateDoesNotListDirectoryWhenMissing() {
        let mock = MockFileSystemChecker()
        mock.directoryExistsResult = false

        _ = evaluatePermissionGate(fileSystem: mock)

        #expect(mock.contentsOfDirectoryCallCount == 0)
    }

    @Test("evaluatePermissionGate calls contentsOfDirectory when directory exists")
    @MainActor
    func evaluateGateListsDirectoryWhenPresent() {
        let mock = MockFileSystemChecker()
        mock.directoryExistsResult = true
        mock.readableResult = true

        _ = evaluatePermissionGate(fileSystem: mock)

        #expect(mock.contentsOfDirectoryCallCount == 1)
    }
}
