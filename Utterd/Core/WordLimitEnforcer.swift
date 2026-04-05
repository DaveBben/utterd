import Core

func enforceWordLimit(_ text: String, limit: Int) -> String {
    if wordCount(text) <= limit { return text }
    return text.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")
}
