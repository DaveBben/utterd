import Foundation
import Testing
import Core
@testable import Utterd

@Suite("SettingsLLMSection")
struct SettingsLLMSectionTests {

    @Test("fresh defaults produce both toggles off")
    @MainActor
    func freshDefaultsBothOff() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        let config = settings.toRoutingConfiguration()
        #expect(config.summarizationEnabled == false)
        #expect(config.titleGenerationEnabled == false)
    }

    @Test("only summarizationEnabled on")
    @MainActor
    func onlySummarizationOn() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.summarizationEnabled = true
        let config = settings.toRoutingConfiguration()
        #expect(config.summarizationEnabled == true)
        #expect(config.titleGenerationEnabled == false)
    }

    @Test("only titleGenerationEnabled on")
    @MainActor
    func onlyTitleGenerationOn() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.titleGenerationEnabled = true
        let config = settings.toRoutingConfiguration()
        #expect(config.summarizationEnabled == false)
        #expect(config.titleGenerationEnabled == true)
    }
}
