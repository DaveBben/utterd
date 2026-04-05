import Core

/// Enforces a word-count limit on the given text.
///
/// When the text is at or under the limit, it is returned unchanged (preserving
/// original whitespace). When over the limit, the text is split on whitespace,
/// truncated to `limit` words, and re-joined with single spaces.
func enforceWordLimit(_ text: String, limit: Int) -> String {
    if wordCount(text) <= limit { return text }
    return text.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")
}
