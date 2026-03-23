import Foundation
@testable import Utterd

// Thread safety: all use is confined to @MainActor test functions.
// @unchecked Sendable is safe because tests never access these from other isolation domains.
final class MockScriptExecutor: ScriptExecutor, @unchecked Sendable {
    nonisolated(unsafe) var executeResults: [Result<String, Error>] = []
    nonisolated(unsafe) var executeCalls: [String] = []

    func execute(script: String) async throws -> String {
        executeCalls.append(script)
        if executeResults.isEmpty {
            return ""
        }
        return try executeResults.removeFirst().get()
    }
}
