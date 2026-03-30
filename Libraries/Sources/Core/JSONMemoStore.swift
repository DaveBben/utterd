import Foundation

/// An actor-based `MemoStore` that persists records as a JSON array on disk.
/// Thread safety is provided by Swift's actor isolation.
public actor JSONMemoStore: MemoStore {

    private let fileURL: URL
    private var records: [MemoRecord]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([MemoRecord].self, from: data) {
            self.records = decoded
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

    // MARK: - Private

    private func write() throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
