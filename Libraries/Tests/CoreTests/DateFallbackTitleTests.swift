import Foundation
import Testing

@testable import Core

@Suite("DateFallbackTitle")
struct DateFallbackTitleTests {
    @Test("Uses local timezone, not UTC")
    func usesLocalTimezone() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let expected = localFormattedDate(date)
        let result = dateFallbackTitle(for: date)

        #expect(result == expected)
    }

    @Test("Output has correct prefix and format")
    func outputFormat() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = dateFallbackTitle(for: date)

        #expect(result.hasPrefix("Voice Memo "))
        // Format: "Voice Memo yyyy-MM-dd HH:mm" — total length is fixed
        // "Voice Memo " = 11 chars, "yyyy-MM-dd HH:mm" = 16 chars
        #expect(result.count == 27)
    }

    // MARK: - Helpers

    private func localFormattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Voice Memo' yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
