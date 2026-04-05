import Foundation
import Observation
import Core

@Observable
@MainActor
final class UserSettings {

    enum Keys {
        static let defaultFolderName = "defaultFolderName"
        static let defaultFolderID = "defaultFolderID"
        static let summarizationEnabled = "summarizationEnabled"
        static let titleGenerationEnabled = "titleGenerationEnabled"
        static let summarizationInstructions = "summarizationInstructions"
        static let migrationVersion = "migrationVersion"
        // Legacy keys removed during migration v1
        static let useCustomPrompt = "useCustomPrompt"
        static let customPrompt = "customPrompt"
        static let llmEnabled = "llmEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var defaultFolderName: String? {
        get {
            access(keyPath: \.defaultFolderName)
            return defaults.string(forKey: Keys.defaultFolderName)
        }
        set {
            withMutation(keyPath: \.defaultFolderName) {
                defaults.set(newValue, forKey: Keys.defaultFolderName)
            }
        }
    }

    var defaultFolderID: String? {
        get {
            access(keyPath: \.defaultFolderID)
            return defaults.string(forKey: Keys.defaultFolderID)
        }
        set {
            withMutation(keyPath: \.defaultFolderID) {
                defaults.set(newValue, forKey: Keys.defaultFolderID)
            }
        }
    }

    var summarizationEnabled: Bool {
        get {
            access(keyPath: \.summarizationEnabled)
            return defaults.bool(forKey: Keys.summarizationEnabled)
        }
        set {
            withMutation(keyPath: \.summarizationEnabled) {
                defaults.set(newValue, forKey: Keys.summarizationEnabled)
            }
        }
    }

    var summarizationInstructions: String? {
        get {
            access(keyPath: \.summarizationInstructions)
            return defaults.string(forKey: Keys.summarizationInstructions)
        }
        set {
            withMutation(keyPath: \.summarizationInstructions) {
                defaults.set(newValue, forKey: Keys.summarizationInstructions)
            }
        }
    }

    var titleGenerationEnabled: Bool {
        get {
            access(keyPath: \.titleGenerationEnabled)
            return defaults.bool(forKey: Keys.titleGenerationEnabled)
        }
        set {
            withMutation(keyPath: \.titleGenerationEnabled) {
                defaults.set(newValue, forKey: Keys.titleGenerationEnabled)
            }
        }
    }

    private static let currentMigrationVersion = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.integer(forKey: Keys.migrationVersion) < Self.currentMigrationVersion {
            defaults.removeObject(forKey: Keys.useCustomPrompt)
            defaults.removeObject(forKey: Keys.customPrompt)
            defaults.removeObject(forKey: Keys.llmEnabled)
            defaults.set(Self.currentMigrationVersion, forKey: Keys.migrationVersion)
        }
    }

    func toRoutingConfiguration() -> RoutingConfiguration {
        UserSettings.readRoutingConfiguration(from: defaults)
    }

    nonisolated static func readRoutingConfiguration(from defaults: UserDefaults = .standard) -> RoutingConfiguration {
        RoutingConfiguration(
            summarizationEnabled: defaults.bool(forKey: Keys.summarizationEnabled),
            titleGenerationEnabled: defaults.bool(forKey: Keys.titleGenerationEnabled),
            defaultFolderName: defaults.string(forKey: Keys.defaultFolderName),
            defaultFolderID: defaults.string(forKey: Keys.defaultFolderID),
            summarizationInstructions: defaults.string(forKey: Keys.summarizationInstructions)
        )
    }
}
