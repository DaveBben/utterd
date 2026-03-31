import Foundation

/// Classifies a transcript into a Notes folder by asking an LLM to pick
/// from the provided hierarchy (or fall back to "GENERAL NOTES").
public struct TranscriptClassifier {

    /// Classifies the transcript and returns a folder path (or nil for general)
    /// plus a short title. The `now` date is used only to generate fallback titles
    /// when the LLM response contains no usable title.
    public static func classify(
        transcript: String,
        hierarchy: [FolderHierarchyEntry],
        using llm: any LLMService,
        now: Date
    ) async throws -> NoteClassificationResult {
        let systemPrompt = buildSystemPrompt(hierarchy: hierarchy)
        let response = try await llm.generate(systemPrompt: systemPrompt, userPrompt: transcript)
        return parse(response: response, hierarchy: hierarchy, now: now)
    }

    // MARK: - Private

    private static func buildSystemPrompt(hierarchy: [FolderHierarchyEntry]) -> String {
        let folderList = hierarchy.map { "- \($0.path)" }.joined(separator: "\n")
        return """
        You are a note routing assistant. Given a voice memo transcript, choose the best folder for the note.

        Available folders (dot notation):
        \(folderList)
        - GENERAL NOTES

        Respond with exactly two lines:
        - line 1: the folder path from the list above (e.g. "finance.home"), or "GENERAL NOTES" if none fits
        - line 2: a short descriptive title for the note (5 words or fewer)

        Do not include any other text.
        """
    }

    private static func parse(
        response: String,
        hierarchy: [FolderHierarchyEntry],
        now: Date
    ) -> NoteClassificationResult {
        let lines = response
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let rawFolder = lines.first ?? ""
        let rawTitle = lines.dropFirst().first ?? ""

        let folderPath = matchFolder(rawFolder, in: hierarchy)
        let title = rawTitle.isEmpty ? dateFallbackTitle(for: now) : rawTitle

        return NoteClassificationResult(folderPath: folderPath, title: title)
    }

    /// Returns the matching hierarchy path (original casing) or nil for GENERAL NOTES / unknown.
    private static func matchFolder(_ raw: String, in hierarchy: [FolderHierarchyEntry]) -> String? {
        let normalized = raw.lowercased()
        guard normalized != "general notes" else { return nil }
        return hierarchy.first { $0.path.lowercased() == normalized }?.path
    }

}
