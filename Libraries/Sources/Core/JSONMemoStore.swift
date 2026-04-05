import Foundation

/// An actor-based `MemoStore` that persists records as a JSON array on disk.
/// Thread safety is provided by Swift's actor isolation.
public actor JSONMemoStore: MemoStore {

    nonisolated let logger: any WatcherLogger
    private let fileURL: URL
    private var records: [MemoRecord]

    public init(fileURL: URL, logger: any WatcherLogger) {
        self.logger = logger
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            do {
                self.records = try JSONDecoder().decode([MemoRecord].self, from: data)
            } catch {
                logger.warning("Corrupt memo store at \(fileURL.lastPathComponent): \(error.localizedDescription). Backing up and starting fresh.")
                let backupURL = fileURL.appendingPathExtension("corrupt-backup")
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
                if !FileManager.default.fileExists(atPath: backupURL.path) {
                    logger.warning("Failed to create backup of corrupt store")
                }
                self.records = []
            }
        } else {
            self.records = []
        }
    }

    public func insert(_ record: MemoRecord) throws {
        let normalized = record.fileURL.standardizedFileURL
        guard !records.contains(where: { $0.fileURL.standardizedFileURL == normalized }) else {
            return
        }
        records.append(record)
        do {
            try write()
        } catch {
            records.removeLast()
            throw MemoStoreError.writeFailed(fileURL, underlying: error)
        }
    }

    public func contains(fileURL url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        return records.contains(where: { $0.fileURL.standardizedFileURL == normalized })
    }

    public func oldestUnprocessed() -> MemoRecord? {
        records
            .filter { $0.dateProcessed == nil }
            .min(by: { $0.dateCreated < $1.dateCreated })
    }

    public func mostRecentlyProcessed() -> MemoRecord? {
        records
            .filter { $0.dateProcessed != nil }
            .max(by: { ($0.dateProcessed ?? .distantPast) < ($1.dateProcessed ?? .distantPast) })
    }

    public func markProcessed(fileURL url: URL, date: Date) throws {
        let normalized = url.standardizedFileURL
        guard let index = records.firstIndex(where: { $0.fileURL.standardizedFileURL == normalized }) else {
            throw MemoStoreError.recordNotFound(url)
        }
        let previousDate = records[index].dateProcessed
        records[index].dateProcessed = date
        do {
            try write()
        } catch {
            records[index].dateProcessed = previousDate
            throw MemoStoreError.writeFailed(fileURL, underlying: error)
        }
    }

    public func markFailed(fileURL: URL, reason: String, date: Date) throws {
        fatalError("Not yet implemented — see Task 1")
    }

    public func allUnprocessed() -> [MemoRecord] {
        fatalError("Not yet implemented — see Task 1")
    }

    // MARK: - Private

    private func write() throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
