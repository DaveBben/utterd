import Core
import Foundation
import Testing
@testable import Utterd

/// Integration tests that exercise `TranscriptClassifier` with the real on-device
/// Foundation Model. Assertions check structural validity (non-empty title, folder
/// is either a known path or nil for GENERAL NOTES). Classification accuracy is
/// logged for visual inspection but not hard-asserted, since the on-device model
/// is non-deterministic.
@Suite("TranscriptClassifier Integration", .tags(.integration))
struct TranscriptClassifierIntegrationTests {

    private let hierarchy: [FolderHierarchyEntry] = [
        entry("Ideas"),
        entry("Ideas.App Ideas"),
        entry("Notes"),
        entry("Projects"),
        entry("Projects.Utterd"),
        entry("Recipes"),
        entry("Work"),
        entry("Work.Meetings"),
    ]

    private var knownPaths: Set<String> {
        Set(hierarchy.map(\.path))
    }

    @Test("classifies app idea transcript and produces valid output")
    func classifiesAppIdea() async throws {
        let result = try await classify("""
        OK, we'll try it again. Let's say I have an app idea that's going to take \
        an article and turn it into a podcast. This app idea can be running locally \
        on your device.
        """)

        assertValidResult(result, expectedFolders: ["Ideas", "Ideas.App Ideas"])
    }

    @Test("classifies recipe transcript and produces valid output")
    func classifiesRecipe() async throws {
        let result = try await classify("""
        So for the pasta sauce you need to start with olive oil and garlic, \
        then add crushed tomatoes and let it simmer for about 30 minutes. \
        Add some fresh basil at the end.
        """)

        assertValidResult(result, expectedFolders: ["Recipes"])
    }

    @Test("classifies work meeting transcript and produces valid output")
    func classifiesWorkMeeting() async throws {
        let result = try await classify("""
        In today's standup we discussed the API migration timeline. \
        Sarah is handling the auth endpoints and Dave is doing the database schema changes. \
        We need to finish by end of sprint.
        """)

        assertValidResult(result, expectedFolders: ["Work", "Work.Meetings"])
    }

    @Test("classifies generic transcript and produces valid output")
    func classifiesGeneral() async throws {
        let result = try await classify(
            "Remind me to call the dentist tomorrow morning"
        )

        assertValidResult(result, expectedFolders: [])
    }

    // MARK: - Helpers

    /// Asserts structural validity and logs classification for visual inspection.
    /// `expectedFolders` is the ideal set — a mismatch is logged as a warning, not a failure,
    /// because the on-device model is non-deterministic.
    private func assertValidResult(
        _ result: NoteClassificationResult,
        expectedFolders: [String]
    ) {
        // Title must always be non-empty
        #expect(!result.title.isEmpty, "Title should not be empty")

        // Folder must be nil (GENERAL NOTES) or a known hierarchy path
        if let folder = result.folderPath {
            #expect(knownPaths.contains(folder), "Unknown folder path: \(folder)")
        }

        // Log accuracy for visual inspection
        let actual = result.folderPath ?? "GENERAL NOTES"
        let expected = expectedFolders.isEmpty ? "GENERAL NOTES" : expectedFolders.joined(separator: " | ")
        let match = expectedFolders.isEmpty
            ? result.folderPath == nil
            : expectedFolders.contains(result.folderPath ?? "")
        print("\(match ? "✓" : "✗") folder: \(actual) (expected: \(expected)), title: \(result.title)")
    }

    private func classify(_ transcript: String) async throws -> NoteClassificationResult {
        try await requireModelAccess()
        guard #available(macOS 26, *) else {
            return NoteClassificationResult(folderPath: nil, title: "")
        }

        let service = FoundationModelLLMService()
        return try await TranscriptClassifier.classify(
            transcript: transcript,
            hierarchy: hierarchy,
            using: service,
            now: Date()
        )
    }
}

// MARK: - Helpers

private func entry(_ path: String) -> FolderHierarchyEntry {
    FolderHierarchyEntry(
        path: path,
        folder: NotesFolder(id: "fake-\(path)", name: path.components(separatedBy: ".").last!, containerID: nil)
    )
}
