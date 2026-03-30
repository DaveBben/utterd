import Core
import Foundation
import Testing
@testable import Utterd

@Suite("PermissionGate")
struct PermissionGateTests {

    // AC: isReadable false -> evaluatePermissionGate returns .showPermissionAlert
    @Test("evaluatePermissionGate returns showPermissionAlert when access is denied")
    @MainActor
    func evaluateGateWhenAccessDenied() {
        let mock = MockFileSystemChecker()
        mock.readableResult = false
        let checker = PermissionChecker(fileSystem: mock)

        let action = evaluatePermissionGate(checker: checker)

        #expect(action == .showPermissionAlert)
    }

    // AC: isReadable true -> evaluatePermissionGate returns .proceed
    @Test("evaluatePermissionGate returns proceed when access is granted")
    @MainActor
    func evaluateGateWhenAccessGranted() {
        let mock = MockFileSystemChecker()
        mock.readableResult = true
        let checker = PermissionChecker(fileSystem: mock)

        let action = evaluatePermissionGate(checker: checker)

        #expect(action == .proceed)
    }

    // E3: handleOpenSystemSettings always calls terminate, even when openURL returns false
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

    // AC: handleOpenSystemSettings passes a URL containing "Privacy_AllFiles" to openURL
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

    // AC: after evaluatePermissionGate returns .proceed, the caller can set permissionResolved = true
    @Test("permissionResolved can be set true after evaluatePermissionGate returns proceed")
    @MainActor
    func permissionResolvedSetAfterProceed() {
        let mock = MockFileSystemChecker()
        mock.readableResult = true
        let checker = PermissionChecker(fileSystem: mock)
        let appState = AppState()

        let action = evaluatePermissionGate(checker: checker)
        if action == .proceed {
            appState.permissionResolved = true
        }

        #expect(appState.permissionResolved == true)
    }
}
