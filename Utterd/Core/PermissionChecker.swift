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
        hasVoiceMemoAccess = fileSystem.isReadable(at: voiceMemoDirectoryURL)
    }
}
