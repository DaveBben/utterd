import Foundation
import Testing

@testable import Core

@Suite("FileWatcherLogger")
struct FileWatcherLoggerTests {

    private func makeTempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "FileWatcherLoggerTests-\(UUID().uuidString).log")
    }

    // AC-4.1: info, warning, error are all written to the file
    @Test("info, warning, and error messages are all written to the file")
    func infoWarningErrorWrittenToFile() throws {
        let url = makeTempURL()
        let logger = FileWatcherLogger(fileURL: url)

        logger.info("alpha")
        logger.warning("beta")
        logger.error("gamma")

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("alpha"))
        #expect(contents.contains("beta"))
        #expect(contents.contains("gamma"))
    }

    // AC-4.3: rotation creates .1 archive and starts fresh file
    @Test("rotation creates archive and fresh file when threshold exceeded")
    func rotationCreatesArchive() throws {
        let url = makeTempURL()
        let rotatedURL = url.appendingPathExtension("1")
        let threshold = 1024
        let logger = FileWatcherLogger(fileURL: url, rotationThreshold: threshold)

        // Write enough data to exceed the threshold.
        // Each line is ~80 bytes; 20 lines = ~1600 bytes, well above 1024.
        for i in 0..<20 {
            logger.info("line-\(i)-padding-to-make-this-line-a-reasonable-length-for-testing")
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        let fileSize = contents.utf8.count

        // Main file should be small (only post-rotation writes)
        let oneLineMax = 200
        #expect(fileSize < threshold + oneLineMax)

        // The last-written line must be present in the main file
        #expect(contents.contains("line-19"))

        // Rotated archive should exist and contain earlier lines
        let rotatedExists = FileManager.default.fileExists(atPath: rotatedURL.path)
        #expect(rotatedExists, "Rotated .1 file should exist")
        if rotatedExists {
            let rotatedContents = try String(contentsOf: rotatedURL, encoding: .utf8)
            #expect(rotatedContents.contains("line-0"))
        }

        // Cleanup
        try? FileManager.default.removeItem(at: rotatedURL)
    }

    // Graceful no-op when file cannot be created
    @Test("no crash and no file when log path is not writable")
    func gracefulNoOpWhenFileNotWritable() {
        let url = URL(fileURLWithPath: "/nonexistent-dir/test.log")
        let logger = FileWatcherLogger(fileURL: url)

        // Must not crash
        logger.info("msg")
        logger.warning("msg")
        logger.error("msg")

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // Log lines include a timestamp and level prefix
    @Test("log line contains timestamp and level prefix")
    func logLineContainsTimestampAndLevel() throws {
        let url = makeTempURL()
        let logger = FileWatcherLogger(fileURL: url)

        logger.info("hello")

        let contents = try String(contentsOf: url, encoding: .utf8)
        // Format: [yyyy-MM-dd HH:mm:ss] [INFO] hello
        #expect(contents.contains("[INFO]"))
        #expect(contents.contains("hello"))
        // Timestamp bracket opens the line
        let lines = contents.split(separator: "\n")
        #expect(lines.first?.hasPrefix("[") == true)
    }
}
