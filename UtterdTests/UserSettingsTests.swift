import Foundation
import Testing
import Core
@testable import Utterd

@Suite("UserSettings")
struct UserSettingsTests {

    // MARK: - Defaults

    @Test("fresh UserDefaults suite has correct defaults")
    @MainActor
    func freshDefaults() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)

        #expect(settings.llmEnabled == false)
        #expect(settings.defaultFolderName == nil)
        #expect(settings.useCustomPrompt == false)
        #expect(settings.customPrompt == TranscriptClassifier.defaultCustomPrompt)
        #expect(settings.summarizationEnabled == false)
    }

    // MARK: - Persistence

    @Test("llmEnabled persists across re-init")
    @MainActor
    func llmEnabledPersists() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.llmEnabled = true

        let reloaded = UserSettings(defaults: defaults)
        #expect(reloaded.llmEnabled == true)
    }

    @Test("defaultFolderName persists across re-init")
    @MainActor
    func defaultFolderNamePersists() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.defaultFolderName = "Work"

        let reloaded = UserSettings(defaults: defaults)
        #expect(reloaded.defaultFolderName == "Work")
    }

    @Test("useCustomPrompt and customPrompt persist across re-init")
    @MainActor
    func customPromptPersists() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.useCustomPrompt = true
        settings.customPrompt = "Custom text"

        let reloaded = UserSettings(defaults: defaults)
        #expect(reloaded.useCustomPrompt == true)
        #expect(reloaded.customPrompt == "Custom text")
    }

    // MARK: - toRoutingConfiguration

    @Test("toRoutingConfiguration with LLM disabled returns .disabled approach")
    @MainActor
    func routingConfigDisabled() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.llmEnabled = false

        let config = settings.toRoutingConfiguration()
        #expect(config.llmApproach == RoutingConfiguration.LLMApproach.disabled)
    }

    @Test("toRoutingConfiguration with LLM enabled and useCustomPrompt false returns .autoRoute")
    @MainActor
    func routingConfigAutoRoute() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.llmEnabled = true
        settings.useCustomPrompt = false

        let config = settings.toRoutingConfiguration()
        #expect(config.llmApproach == RoutingConfiguration.LLMApproach.autoRoute)
    }

    @Test("toRoutingConfiguration with LLM enabled and useCustomPrompt true returns .customPrompt")
    @MainActor
    func routingConfigCustomPrompt() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.llmEnabled = true
        settings.useCustomPrompt = true
        settings.customPrompt = "Custom text"

        let config = settings.toRoutingConfiguration()
        #expect(config.llmApproach == RoutingConfiguration.LLMApproach.customPrompt("Custom text"))
    }

    @Test("toRoutingConfiguration maps summarizationEnabled and defaultFolderName")
    @MainActor
    func routingConfigMapsAllFields() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.summarizationEnabled = true
        settings.defaultFolderName = "Personal"

        let config = settings.toRoutingConfiguration()
        #expect(config.summarizationEnabled == true)
        #expect(config.defaultFolderName == "Personal")
    }
}
