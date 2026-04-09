#if compiler(>=6.2)
import Foundation
import Testing
import Core
@testable import Utterd

@Suite("SpeechAnalyzerTranscriptionService")
struct SpeechAnalyzerTranscriptionServiceTests {
    @Test("transcribe throws when file does not exist")
    func transcribeThrowsForNonexistentFile() async throws {
        guard #available(macOS 26, *) else { return }
        let service = SpeechAnalyzerTranscriptionService()
        let nonexistent = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).m4a")

        await #expect(throws: (any Error).self) {
            try await service.transcribe(fileURL: nonexistent)
        }
    }

}
#endif
