import Foundation

public final class FileWatcherLogger: WatcherLogger, @unchecked Sendable {
    private let fileURL: URL
    private let rotationThreshold: Int
    private let lock = NSLock()
    private var fileHandle: FileHandle?

    public init(fileURL: URL, rotationThreshold: Int = 10 * 1024 * 1024) {
        self.fileURL = fileURL
        self.rotationThreshold = rotationThreshold
        self.fileHandle = Self.openOrCreate(at: fileURL)
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
        let line = formatLine(level: level, message: message)
        guard let data = line.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let handle = fileHandle else { return }
        let currentSize = (try? handle.seekToEnd()) ?? 0
        if Int(currentSize) + data.count > rotationThreshold {
            try? handle.truncate(atOffset: 0)
            try? handle.seek(toOffset: 0)
        }
        try? handle.write(contentsOf: data)
    }

    private func formatLine(level: String, message: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        return "[\(timestamp)] [\(level)] \(message)\n"
    }
}
