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

    @Test("Produces Gregorian year regardless of device locale")
    func localeStability() {
        // 2023-11-14 in Gregorian; would be 1445 in Hijri calendar
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = dateFallbackTitle(for: date)

        // Extract the year portion (index 11..<15 of "Voice Memo yyyy-...")
        let yearStr = String(result.dropFirst(11).prefix(4))
        #expect(yearStr == "2023")
    }

    // MARK: - Helpers

    private func localFormattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'Voice Memo' yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
