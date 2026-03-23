import Testing
@testable import Core

@Suite("Core Module")
struct CoreTests {
    @Test("Version is set")
    func versionExists() {
        #expect(!Core.version.isEmpty)
    }
}
