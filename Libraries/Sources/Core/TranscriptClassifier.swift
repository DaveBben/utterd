import Foundation

/// Classifies a transcript into a Notes folder by asking an LLM to pick
/// from the provided hierarchy (or fall back to "GENERAL NOTES").
public struct TranscriptClassifier {

    /// Template for custom prompts. Mirrors the built-in prompt structure but uses
    /// `{notes_folders}` as a placeholder for the dynamic folder list.
    public static let defaultCustomPrompt = """
        Pick the best folder for a voice memo. Reply with exactly two lines: the folder path, then a short title.

        Folders:
        {notes_folders}
        - GENERAL NOTES

        Examples:

        Transcript: "I had this idea for a fitness app that uses your camera to count reps"
        Ideas.App Ideas
        Fitness Rep Counter App

        Transcript: "In the Monday sync we went over the launch timeline with the team"
        Work.Meetings
        Monday Launch Timeline Sync

        Transcript: "Pick up the best folder that matches the topic. If nothing fits, use GENERAL NOTES"
        GENERAL NOTES
        Folder Selection Reminder

        Now classify this transcript. Two lines only: folder path, then title.
        """

    /// Classifies the transcript and returns a folder path (or nil for general)
    /// plus a short title. The `now` date is used only to generate fallback titles
    /// when the LLM response contains no usable title.
    ///
    /// Pass `customSystemPrompt` to override the built-in prompt. The placeholder
    /// `{notes_folders}` is replaced with the list of top-level folder names.
    public static func classify(
        transcript: String,
        hierarchy: [FolderHierarchyEntry],
        using llm: any LLMService,
        customSystemPrompt: String? = nil,
        now: Date
    ) async throws -> NoteClassificationResult {
        let systemPrompt: String
        if let customSystemPrompt {
            let topLevelFolders = hierarchy
                .filter { !$0.path.contains(".") }
                .map { "- \($0.folder.name)" }
                .joined(separator: "\n")
            systemPrompt = customSystemPrompt.replacingOccurrences(of: "{notes_folders}", with: topLevelFolders)
        } else {
            systemPrompt = buildSystemPrompt(hierarchy: hierarchy)
        }
        let response = try await llm.generate(systemPrompt: systemPrompt, userPrompt: transcript)
        return parse(response: response, hierarchy: hierarchy, now: now)
    }

    // MARK: - Private

    private static func buildSystemPrompt(hierarchy: [FolderHierarchyEntry]) -> String {
        let folderList = hierarchy.map { "- \($0.path)" }.joined(separator: "\n")
        return """
        Pick the best folder for a voice memo. Reply with exactly two lines: the folder path, then a short title.

        Folders:
        \(folderList)
        - GENERAL NOTES

        Examples:

        Transcript: "I had this idea for a fitness app that uses your camera to count reps"
        Ideas.App Ideas
        Fitness Rep Counter App

        Transcript: "In the Monday sync we went over the launch timeline with the team"
        Work.Meetings
        Monday Launch Timeline Sync

        Transcript: "Pick up the best folder that matches the topic. If nothing fits, use GENERAL NOTES"
        GENERAL NOTES
        Folder Selection Reminder

        Now classify this transcript. Two lines only: folder path, then title.
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
            .map { stripLabel($0) }

        let rawFolder = lines.first ?? ""
        let rawTitle = lines.dropFirst().first ?? ""

        let folderPath = matchFolder(rawFolder, in: hierarchy)
        let title = rawTitle.isEmpty ? dateFallbackTitle(for: now) : rawTitle

        return NoteClassificationResult(folderPath: folderPath, title: title)
    }

    /// Strips common prefixes the on-device model sometimes adds (e.g. "Folder: Ideas" → "Ideas").
    private static func stripLabel(_ line: String) -> String {
        for prefix in ["folder:", "title:", "line 1:", "line 2:", "path:"] {
            if line.lowercased().hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }

    /// Returns the matching hierarchy path (original casing) or nil for GENERAL NOTES / unknown.
    private static func matchFolder(_ raw: String, in hierarchy: [FolderHierarchyEntry]) -> String? {
        let normalized = raw.lowercased()
        guard normalized != "general notes" else { return nil }
        return hierarchy.first { $0.path.lowercased() == normalized }?.path
    }

}
