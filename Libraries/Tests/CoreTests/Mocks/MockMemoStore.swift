import Foundation
@testable import Core

actor MockMemoStore: MemoStore {
    var insertedRecords: [MemoRecord] = []
    var markProcessedCalls: [(fileURL: URL, date: Date)] = []
    var insertError: Error?
    var oldestUnprocessedResult: MemoRecord?

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
        oldestUnprocessedResult
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
