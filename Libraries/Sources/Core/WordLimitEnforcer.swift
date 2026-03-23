/// Truncates text to the given word limit.
///
/// When the text is at or under the limit, it is returned unchanged (preserving
/// original whitespace). When over the limit, the text is split on whitespace,
/// truncated to `limit` words, and re-joined with single spaces.
///
/// Uses the same whitespace-splitting strategy as ``wordCount(_:)`` to ensure
/// consistent word counting across the codebase.
public func truncateToWordLimit(_ text: String, limit: Int) -> String {
    precondition(limit >= 0, "Word limit must be non-negative, got \(limit)")
    if wordCount(text) <= limit { return text }
    return text.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")
}
