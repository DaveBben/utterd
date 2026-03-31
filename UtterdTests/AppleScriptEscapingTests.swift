import Testing
@testable import Utterd

@Suite("String.appleScriptEscaped")
struct AppleScriptEscapingTests {
    @Test("plain string passes through unchanged")
    func plainString() {
        #expect("hello".appleScriptEscaped == "hello")
    }

    @Test("double quotes are escaped")
    func doubleQuotes() {
        #expect(#"He said "hello""#.appleScriptEscaped == #"He said \"hello\""#)
    }

    @Test("backslashes are escaped")
    func backslashes() {
        #expect(#"path\to\file"#.appleScriptEscaped == #"path\\to\\file"#)
    }

    @Test("backslash-quote combination escapes backslash first")
    func backslashQuote() {
        // Input:  She said \"hi\"  (backslash then quote)
        // Output: She said \\\"hi\\\"  (backslash escaped, then quote escaped)
        #expect(#"She said \"hi\""#.appleScriptEscaped == #"She said \\\"hi\\\""#)
    }

    @Test("empty string returns empty string")
    func emptyString() {
        #expect("".appleScriptEscaped == "")
    }

    @Test("unicode and emoji pass through unchanged")
    func unicodeAndEmoji() {
        #expect("Hello, 世界 🎉".appleScriptEscaped == "Hello, 世界 🎉")
    }

    @Test("carriage return is replaced with newline")
    func carriageReturn() {
        let withCR = "line1\u{000D}line2"
        let expected = "line1\nline2"
        #expect(withCR.appleScriptEscaped == expected)
    }
}
