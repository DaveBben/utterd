import Core
import Foundation

struct NSAppleScriptExecutor: ScriptExecutor {
    func execute(script source: String) async throws -> String {
        try await MainActor.run {
            guard let script = NSAppleScript(source: source) else {
                throw NotesServiceError.scriptExecutionFailed("Failed to initialize NSAppleScript")
            }

            var errorInfo: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorInfo)

            if let errorInfo {
                let errorNumber = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                // -1743 = errAEEventNotPermitted — user denied Automation permission for this app
                if errorNumber == -1743 {
                    throw NotesServiceError.automationPermissionDenied
                }
                let description = (errorInfo[NSAppleScript.errorMessage] as? String)
                    ?? "AppleScript error \(errorNumber)"
                throw NotesServiceError.scriptExecutionFailed(description)
            }

            return descriptor.stringValue ?? ""
        }
    }
}
