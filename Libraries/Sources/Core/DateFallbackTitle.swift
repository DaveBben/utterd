import Foundation

/// Generates a date-based fallback title when the LLM response is missing one.
func dateFallbackTitle(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "'Voice Memo' yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}
