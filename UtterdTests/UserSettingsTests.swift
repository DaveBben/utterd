import Foundation
import Testing
import Core
@testable import Utterd

@Suite("UserSettings")
struct UserSettingsTests {

    @Test("fresh UserDefaults suite has correct defaults")
    @MainActor
    func freshDefaults() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)

        #expect(settings.summarizationEnabled == false)
        #expect(settings.titleGenerationEnabled == false)
        #expect(settings.defaultFolderName == nil)
    }

    @Test("titleGenerationEnabled persists across re-init")
    @MainActor
    func titleGenerationEnabledPersists() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.titleGenerationEnabled = true

        let reloaded = UserSettings(defaults: defaults)
        #expect(reloaded.titleGenerationEnabled == true)
    }

    @Test("summarizationEnabled persists across re-init")
    @MainActor
    func summarizationEnabledPersists() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.summarizationEnabled = true

        let reloaded = UserSettings(defaults: defaults)
        #expect(reloaded.summarizationEnabled == true)
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

    @Test("toRoutingConfiguration with both false")
    @MainActor
    func routingConfigBothFalse() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        let config = settings.toRoutingConfiguration()
        #expect(config == RoutingConfiguration(summarizationEnabled: false, titleGenerationEnabled: false))
    }

    @Test("toRoutingConfiguration with both true")
    @MainActor
    func routingConfigBothTrue() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.summarizationEnabled = true
        settings.titleGenerationEnabled = true

        let config = settings.toRoutingConfiguration()
        #expect(config == RoutingConfiguration(summarizationEnabled: true, titleGenerationEnabled: true))
    }

    @Test("toRoutingConfiguration maps defaultFolderName correctly")
    @MainActor
    func routingConfigMapsAllFields() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = UserSettings(defaults: defaults)
        settings.summarizationEnabled = true
        settings.defaultFolderName = "Work"

        let config = settings.toRoutingConfiguration()
        #expect(config.summarizationEnabled == true)
        #expect(config.titleGenerationEnabled == false)
        #expect(config.defaultFolderName == "Work")
    }

    @Test("stale UserDefaults keys removed on init")
    @MainActor
    func staleKeyCleanup() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "useCustomPrompt")
        defaults.set("old prompt", forKey: "customPrompt")
        defaults.set(true, forKey: "llmEnabled")

        _ = UserSettings(defaults: defaults)

        #expect(defaults.object(forKey: "useCustomPrompt") == nil)
        #expect(defaults.object(forKey: "customPrompt") == nil)
        #expect(defaults.object(forKey: "llmEnabled") == nil)
    }
}
