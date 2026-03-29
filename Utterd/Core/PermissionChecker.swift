import Core
import Foundation
import Observation

@Observable
@MainActor
final class PermissionChecker {
    var hasVoiceMemoAccess: Bool = false

    private let fileSystem: FileSystemChecker

    var voiceMemoDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")
    }

    init(fileSystem: FileSystemChecker) {
        self.fileSystem = fileSystem
    }

    func checkAccess() {
        // Attempt a directory listing to trigger TCC registration. This ensures Utterd
        // appears in System Settings > Full Disk Access so the user can find and enable it.
        // isReadableFile alone does not trigger TCC registration on macOS.
        _ = fileSystem.contentsOfDirectory(at: voiceMemoDirectoryURL)
        hasVoiceMemoAccess = fileSystem.isReadable(at: voiceMemoDirectoryURL)
    }
}
