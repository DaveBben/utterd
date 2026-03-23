import Foundation
@testable import Core

actor MockMemoStore: MemoStore {
    var insertedRecords: [MemoRecord] = []
    var markProcessedCalls: [(fileURL: URL, date: Date)] = []
    var markFailedCalls: [(fileURL: URL, reason: String, date: Date)] = []
    var failedURLs: Set<URL> = []
    var insertError: Error?
    var oldestUnprocessedResult: MemoRecord?
    var allUnprocessedResult: [MemoRecord] = []
    var mostRecentlyProcessedResult: MemoRecord?
    var mostRecentlyProcessedCallCount: Int = 0

    func insert(_ record: MemoRecord) async throws {
        if let error = insertError {
            throw error
        }
        insertedRecords.append(record)
    }

    func contains(fileURL: URL) async -> Bool {
        insertedRecords.contains { $0.fileURL == fileURL }
    }

    func oldestUnprocessed() async -> MemoRecord? {
        guard let result = oldestUnprocessedResult else { return nil }
        return failedURLs.contains(result.fileURL) ? nil : result
    }

    func markFailed(fileURL: URL, reason: String, date: Date) async throws {
        markFailedCalls.append((fileURL: fileURL, reason: reason, date: date))
        failedURLs.insert(fileURL)
    }

    func allUnprocessed() async -> [MemoRecord] {
        allUnprocessedResult
    }

    func mostRecentlyProcessed() async -> MemoRecord? {
        mostRecentlyProcessedCallCount += 1
        return mostRecentlyProcessedResult
    }

    func markProcessed(fileURL: URL, date: Date) async throws {
        markProcessedCalls.append((fileURL: fileURL, date: date))
    }

    func setInsertError(_ error: Error?) {
        self.insertError = error
    }

    func setOldestUnprocessed(_ record: MemoRecord?) {
        self.oldestUnprocessedResult = record
    }
}
