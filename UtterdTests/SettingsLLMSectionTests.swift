import Foundation
import Testing
@testable import Utterd
import Core

@Suite("SettingsLLMSection")
struct SettingsLLMSectionTests {
    @Test("LLM disabled produces .disabled configuration regardless of other settings")
    @MainActor
    func llmDisabledProducesDisabledConfig() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.llmEnabled = false
        settings.useCustomPrompt = true
        settings.customPrompt = "Custom"
        settings.summarizationEnabled = true

        let config = settings.toRoutingConfiguration()
        #expect(config.llmApproach == .disabled)
    }

    @Test("Assigning defaultCustomPrompt to customPrompt round-trips correctly")
    @MainActor
    func resetToDefaultRestoresPrompt() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.customPrompt = "Edited prompt"
        #expect(settings.customPrompt == "Edited prompt")

        settings.customPrompt = TranscriptClassifier.defaultCustomPrompt
        #expect(settings.customPrompt == TranscriptClassifier.defaultCustomPrompt)
    }

    @Test("Summarization enabled with LLM disabled still produces .disabled config")
    @MainActor
    func summarizationWithLLMDisabledStillDisabled() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.summarizationEnabled = true
        settings.llmEnabled = false

        let config = settings.toRoutingConfiguration()
        #expect(config.llmApproach == .disabled)
    }
}
