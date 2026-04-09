import Foundation
import Testing

extension Tag {
    @Tag static var integration: Self
}

#if compiler(>=6.2)
import Core
@testable import Utterd

/// Guards integration tests that require macOS 26+ and a downloaded Foundation Model.
/// Skips the test on older macOS; records a diagnostic if the model is unavailable.
func requireModelAccess() async throws {
    guard #available(macOS 26, *) else {
        try #require(Bool(false), "Requires macOS 26+ — skipping")
        return
    }
    let service = FoundationModelLLMService()
    do {
        _ = try await service.generate(systemPrompt: "Respond with: ok", userPrompt: "test")
    } catch {
        Issue.record("Foundation Model is not available — model may not be downloaded. Error: \(error)")
        throw error
    }
}
#endif
