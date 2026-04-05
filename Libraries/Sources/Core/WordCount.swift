/// Returns the number of whitespace-separated words in the given text.
///
/// Uses the same splitting strategy as the summarizer's word chunking,
/// ensuring consistency between UI word limits and budget calculations.
public func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}
