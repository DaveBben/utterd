#if compiler(>=6.2)
import Foundation
import Testing
import Core
@testable import Utterd

/// Integration test that exercises the full on-device transcription pipeline
/// against a real audio file. Requires macOS 26+ and downloaded speech models.
///
/// The test fixture lives at UtterdTests/Fixtures/test.m4a. To update it,
/// replace that file with any short voice memo.
@Suite("SpeechAnalyzer Transcription Integration", .tags(.integration))
struct SpeechAnalyzerTranscriptionIntegrationTests {

    /// Locates the Fixtures folder inside the test bundle.
    private func fixtureURL(named filename: String) throws -> URL {
        let bundle = Bundle(for: BundleAnchor.self)
        guard let fixturesURL = bundle.url(forResource: "Fixtures", withExtension: nil) else {
            throw FixtureError.fixturesDirectoryNotFound
        }
        let url = fixturesURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.fileNotFound(filename)
        }
        return url
    }

    @Test("transcribes test.m4a and returns non-empty transcript")
    func transcribeTestFile() async throws {
        guard #available(macOS 26, *) else { return }

        let fileURL = try fixtureURL(named: "test.m4a")
        let service = SpeechAnalyzerTranscriptionService()

        let result = try await service.transcribe(fileURL: fileURL)

        #expect(!result.transcript.isEmpty, "Transcript should not be empty")
        #expect(result.fileURL == fileURL)
        print("Transcribed: \(result.transcript)")
    }
}

// MARK: - Helpers

/// Anchor class used to locate the test bundle at runtime.
/// `Bundle(for:)` requires a class, not a struct.
private class BundleAnchor {}

private enum FixtureError: Error, CustomStringConvertible {
    case fixturesDirectoryNotFound
    case fileNotFound(String)

    var description: String {
        switch self {
        case .fixturesDirectoryNotFound:
            "Could not find Fixtures directory in test bundle"
        case .fileNotFound(let name):
            "Fixture file '\(name)' not found in Fixtures directory"
        }
    }
}
#endif
