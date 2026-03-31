import Core
import Foundation
import FoundationModels

@available(macOS 26, *)
struct FoundationModelLLMService: LLMService {
    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: userPrompt)
        return String(response.content)
    }
}
