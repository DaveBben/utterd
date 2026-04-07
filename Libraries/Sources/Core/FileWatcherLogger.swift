import Foundation

public final class FileWatcherLogger: WatcherLogger, @unchecked Sendable {
    private let fileURL: URL
    private let rotationThreshold: Int
    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter

    public init(fileURL: URL, rotationThreshold: Int = 10 * 1024 * 1024) {
        self.fileURL = fileURL
        self.rotationThreshold = rotationThreshold
        self.fileHandle = Self.openOrCreate(at: fileURL)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.dateFormatter = formatter
    }

    deinit {
        lock.lock()
        fileHandle?.closeFile()
        lock.unlock()
    }

    private static func openOrCreate(at url: URL) -> FileHandle? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil) else { return nil }
        }
        return try? FileHandle(forUpdating: url)
    }

    public func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    public func warning(_ message: String) {
        write(level: "WARNING", message: message)
    }

    public func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    private func write(level: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = formatLine(level: level, message: message)
        guard let data = line.data(using: .utf8) else { return }
        guard fileHandle != nil else { return }
        let currentSize = (try? fileHandle?.seekToEnd()) ?? 0
        if Int(currentSize) + data.count > rotationThreshold {
            rotate()
        }
        try? fileHandle?.write(contentsOf: data)
    }

    /// Rotates the current log file to `.1` and opens a fresh file.
    /// Single generation — only the most recent rotated file is preserved.
    /// Must be called while holding `lock`.
    private func rotate() {
        fileHandle?.closeFile()
        fileHandle = nil

        let fm = FileManager.default
        let rotatedURL = fileURL.appendingPathExtension("1")
        do {
            // Remove old rotated file if it exists
            try? fm.removeItem(at: rotatedURL)
            try fm.moveItem(at: fileURL, to: rotatedURL)
        } catch {
            // Last-resort: if rename fails, truncate as fallback
            fileHandle = Self.openOrCreate(at: fileURL)
            return
        }

        fileHandle = Self.openOrCreate(at: fileURL)
    }

    private func formatLine(level: String, message: String) -> String {
        let timestamp = dateFormatter.string(from: Date())
        return "[\(timestamp)] [\(level)] \(message)\n"
    }
}
