import Core
import Foundation

// MARK: - String escaping

extension String {
    /// Escapes a string for safe interpolation into an AppleScript double-quoted string literal.
    ///
    /// Order matters: backslashes must be escaped before quotes to avoid double-escaping.
    /// Carriage returns (U+000D) are replaced with newlines (U+000A) because AppleScript
    /// string literals cannot contain bare CR characters.
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - ScriptExecutor protocol

/// Abstracts AppleScript execution to allow test injection via `MockScriptExecutor`.
protocol ScriptExecutor: Sendable {
    func execute(script: String) async throws -> String
}
