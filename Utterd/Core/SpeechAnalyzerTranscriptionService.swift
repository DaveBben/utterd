import Core
import Foundation
import Speech

@available(macOS 26, *)
struct SpeechAnalyzerTranscriptionService: TranscriptionService {
    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SpeechAnalyzerTranscriptionError.fileNotFound(fileURL)
        }

        let audioFile = try AVAudioFile(forReading: fileURL)
        // Locale.current can return a "fixed" composite locale (e.g. "en_US (fixed)")
        // that SpeechAnalyzer doesn't recognize. Constructing a fresh Locale from the
        // identifier strips the fixed qualifier and matches an allocated locale.
        let locale = Locale(identifier: Locale.current.identifier)
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        let analyzer = try await SpeechAnalyzer(modules: [transcriber])

        async let transcriptFuture = transcriber.results.reduce("") { text, result in
            text + String(result.text.characters)
        }

        let lastSample = try await analyzer.analyzeSequence(from: audioFile)

        if let lastSample {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let transcript = try await transcriptFuture
        return TranscriptionResult(transcript: transcript, fileURL: fileURL)
    }
}

enum SpeechAnalyzerTranscriptionError: Error {
    case fileNotFound(URL)
}
