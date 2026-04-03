import Foundation
import Observation
import Core

@Observable
@MainActor
final class UserSettings {

    enum Keys {
        static let llmEnabled = "llmEnabled"
        static let defaultFolderName = "defaultFolderName"
        static let useCustomPrompt = "useCustomPrompt"
        static let customPrompt = "customPrompt"
        static let summarizationEnabled = "summarizationEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var llmEnabled: Bool {
        get {
            access(keyPath: \.llmEnabled)
            return defaults.bool(forKey: Keys.llmEnabled)
        }
        set {
            withMutation(keyPath: \.llmEnabled) {
                defaults.set(newValue, forKey: Keys.llmEnabled)
            }
        }
    }

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

    var useCustomPrompt: Bool {
        get {
            access(keyPath: \.useCustomPrompt)
            return defaults.bool(forKey: Keys.useCustomPrompt)
        }
        set {
            withMutation(keyPath: \.useCustomPrompt) {
                defaults.set(newValue, forKey: Keys.useCustomPrompt)
            }
        }
    }

    var customPrompt: String {
        get {
            access(keyPath: \.customPrompt)
            return defaults.string(forKey: Keys.customPrompt) ?? TranscriptClassifier.defaultCustomPrompt
        }
        set {
            withMutation(keyPath: \.customPrompt) {
                defaults.set(newValue, forKey: Keys.customPrompt)
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func toRoutingConfiguration() -> RoutingConfiguration {
        UserSettings.readRoutingConfiguration(from: defaults)
    }

    nonisolated static func readRoutingConfiguration(from defaults: UserDefaults = .standard) -> RoutingConfiguration {
        let llmEnabled = defaults.bool(forKey: Keys.llmEnabled)
        let useCustomPrompt = defaults.bool(forKey: Keys.useCustomPrompt)
        let customPrompt = defaults.string(forKey: Keys.customPrompt) ?? TranscriptClassifier.defaultCustomPrompt
        let summarizationEnabled = defaults.bool(forKey: Keys.summarizationEnabled)
        let defaultFolderName = defaults.string(forKey: Keys.defaultFolderName)
        let approach: RoutingConfiguration.LLMApproach
        if !llmEnabled {
            approach = .disabled
        } else if useCustomPrompt {
            approach = .customPrompt(customPrompt)
        } else {
            approach = .autoRoute
        }
        return RoutingConfiguration(
            llmApproach: approach,
            defaultFolderName: defaultFolderName,
            summarizationEnabled: summarizationEnabled
        )
    }
}
