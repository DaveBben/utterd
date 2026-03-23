import Foundation
import Testing
@testable import Utterd

@Suite("RealFileSystemChecker")
struct RealFileSystemCheckerTests {
    @Test("isReadable returns true for a known-readable path")
    func isReadableReturnsTrueForExistingPath() {
        let checker = RealFileSystemChecker()
        let tempDir = FileManager.default.temporaryDirectory

        #expect(checker.isReadable(at: tempDir) == true)
    }

    @Test("isReadable returns false for a nonexistent path")
    func isReadableReturnsFalseForNonexistentPath() {
        let checker = RealFileSystemChecker()
        let nonexistent = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")

        #expect(checker.isReadable(at: nonexistent) == false)
    }
}
