import Foundation
import Observation
import Core

@Observable
@MainActor
final class UserSettings {

    enum Keys {
        static let defaultFolderName = "defaultFolderName"
        static let summarizationEnabled = "summarizationEnabled"
        static let titleGenerationEnabled = "titleGenerationEnabled"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: "useCustomPrompt")
        defaults.removeObject(forKey: "customPrompt")
        defaults.removeObject(forKey: "llmEnabled")
    }

    func toRoutingConfiguration() -> RoutingConfiguration {
        UserSettings.readRoutingConfiguration(from: defaults)
    }

    nonisolated static func readRoutingConfiguration(from defaults: UserDefaults = .standard) -> RoutingConfiguration {
        RoutingConfiguration(
            summarizationEnabled: defaults.bool(forKey: Keys.summarizationEnabled),
            titleGenerationEnabled: defaults.bool(forKey: Keys.titleGenerationEnabled),
            defaultFolderName: defaults.string(forKey: Keys.defaultFolderName)
        )
    }
}
