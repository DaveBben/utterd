import Testing

@testable import Core

@Suite("WordLimitEnforcer")
struct WordLimitEnforcerTests {

    @Test("empty string returns empty string")
    func emptyString() {
        #expect(truncateToWordLimit("", limit: 300) == "")
    }

    @Test("under limit returns text unchanged")
    func underLimit() {
        #expect(truncateToWordLimit("one two three", limit: 300) == "one two three")
    }

    @Test("exactly 300 words returns all 300 words")
    func exactlyAtLimit() {
        let words = (1...300).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let result = truncateToWordLimit(text, limit: 300)
        #expect(result == text)
    }

    @Test("301 words returns first 300 words joined by spaces")
    func oneOverLimit() {
        let words = (1...301).map { "word\($0)" }
        let text = words.joined(separator: " ")
        let expected = words.prefix(300).joined(separator: " ")
        let result = truncateToWordLimit(text, limit: 300)
        #expect(result == expected)
    }

    @Test("under limit with extra whitespace returns text unchanged, preserving original whitespace")
    func preservesWhitespaceWhenUnderLimit() {
        let text = "  spaced  out  "
        #expect(truncateToWordLimit(text, limit: 300) == text)
    }

    @Test("301 words with mixed whitespace truncates to 300 words rejoined with spaces")
    func mixedWhitespaceTruncation() {
        let words = (1...301).map { "word\($0)" }
        var parts: [String] = []
        for (index, word) in words.enumerated() {
            parts.append(word)
            if index < words.count - 1 {
                switch index % 3 {
                case 0: parts.append("\t")
                case 1: parts.append("\n")
                default: parts.append(" ")
                }
            }
        }
        let text = parts.joined()
        let expected = words.prefix(300).joined(separator: " ")
        let result = truncateToWordLimit(text, limit: 300)
        #expect(result == expected)
    }

    @Test("limit of 1 returns only the first word")
    func limitOfOne() {
        #expect(truncateToWordLimit("hello world", limit: 1) == "hello")
    }
}
