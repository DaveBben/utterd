import Core
import Testing
@testable import Utterd

@Suite("PermissionChecker")
struct PermissionCheckerTests {

    // AC-04.1: readable -> hasVoiceMemoAccess = true
    @Test("checkAccess sets hasVoiceMemoAccess true when directory is readable")
    @MainActor
    func checkAccessWhenReadable() {
        let mock = MockFileSystemChecker()
        mock.readableResult = true
        let checker = PermissionChecker(fileSystem: mock)

        checker.checkAccess()

        #expect(checker.hasVoiceMemoAccess == true)
    }

    // AC-04.2: not readable -> hasVoiceMemoAccess = false
    // Covers both E1 (directory doesn't exist) and E2 (not readable for other reasons)
    // because isReadable returns false in both cases.
    @Test("checkAccess sets hasVoiceMemoAccess false when directory is not readable")
    @MainActor
    func checkAccessWhenNotReadable() {
        let mock = MockFileSystemChecker()
        mock.readableResult = false
        let checker = PermissionChecker(fileSystem: mock)

        checker.checkAccess()

        #expect(checker.hasVoiceMemoAccess == false)
    }

    // AC-04.3 (part 1): voiceMemoDirectoryURL path ends with expected suffix
    @Test("voiceMemoDirectoryURL ends with the expected Voice Memos path component")
    @MainActor
    func voiceMemoDirectoryURLPath() {
        let checker = PermissionChecker(fileSystem: MockFileSystemChecker())

        #expect(checker.voiceMemoDirectoryURL.path.hasSuffix(
            "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
        ))
    }

    // AC-04.3 (part 2): checkAccess passes voiceMemoDirectoryURL to isReadable
    @Test("checkAccess calls isReadable with voiceMemoDirectoryURL")
    @MainActor
    func checkAccessUsesCorrectURL() {
        let mock = MockFileSystemChecker()
        let checker = PermissionChecker(fileSystem: mock)

        checker.checkAccess()

        #expect(mock.isReadableCalledWith.contains(checker.voiceMemoDirectoryURL))
    }
}
