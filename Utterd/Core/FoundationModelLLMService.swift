import Core
import Foundation

#if compiler(>=6.2)
import FoundationModels

/// On-device LLM provider using Apple's Foundation Model framework (macOS 26+).
///
/// Creates a fresh `LanguageModelSession` per call — each generation is stateless
/// with no conversation history carried across calls. This is intentional: the
/// classifier and summarizer each provide their own system prompt per request.
@available(macOS 26, *)
struct FoundationModelLLMService: LLMService {
    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: userPrompt)
        return String(response.content)
    }
}
#endif
