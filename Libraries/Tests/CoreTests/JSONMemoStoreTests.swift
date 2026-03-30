import Foundation
import Testing

@testable import Core

@Suite("JSONMemoStore")
struct JSONMemoStoreTests {

    // MARK: - Helpers

    private func makeStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "JSONMemoStoreTests-\(UUID().uuidString).json")
    }

    private func makeRecord(path: String, createdAt offset: TimeInterval = 0) -> MemoRecord {
        MemoRecord(
            fileURL: URL(fileURLWithPath: path),
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000 + offset)
        )
    }

    // MARK: - insert

    @Test("Insert new record: persisted and contains returns true")
    func insertNewRecord() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let record = makeRecord(path: "/memos/a.m4a")

        try await store.insert(record)

        let found = await store.contains(fileURL: record.fileURL)
        #expect(found == true)
    }

    @Test("Insert duplicate: no-op, no error, no duplicate record")
    func insertDuplicateIsNoOp() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let record = makeRecord(path: "/memos/a.m4a")

        try await store.insert(record)
        try await store.insert(record) // second insert — should be silent no-op

        // Reload from disk and verify only one record
        let reloaded = JSONMemoStore(fileURL: storeURL)
        let oldest = await reloaded.oldestUnprocessed()
        #expect(oldest?.fileURL == record.fileURL)

        // contains still true
        let found = await store.contains(fileURL: record.fileURL)
        #expect(found == true)
    }

    // MARK: - contains

    @Test("contains returns false for missing URL")
    func containsReturnsFalseForMissingURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let url = URL(fileURLWithPath: "/memos/missing.m4a")

        let found = await store.contains(fileURL: url)
        #expect(found == false)
    }

    @Test("contains returns true for existing URL")
    func containsReturnsTrueForExistingURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let record = makeRecord(path: "/memos/b.m4a")

        try await store.insert(record)

        let found = await store.contains(fileURL: record.fileURL)
        #expect(found == true)
    }

    // MARK: - oldestUnprocessed

    @Test("oldestUnprocessed returns record created earliest")
    func oldestUnprocessedReturnsEarliest() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)

        let r1 = makeRecord(path: "/memos/r1.m4a", createdAt: 100)
        let r2 = makeRecord(path: "/memos/r2.m4a", createdAt: 200)
        let r3 = makeRecord(path: "/memos/r3.m4a", createdAt: 300)

        // Insert out of order
        try await store.insert(r2)
        try await store.insert(r3)
        try await store.insert(r1)

        let oldest = await store.oldestUnprocessed()
        #expect(oldest?.fileURL == r1.fileURL)
    }

    @Test("oldestUnprocessed returns nil when all records are processed")
    func oldestUnprocessedReturnsNilWhenAllProcessed() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let processed = Date(timeIntervalSince1970: 1_700_099_000)

        let r1 = MemoRecord(
            fileURL: URL(fileURLWithPath: "/memos/r1.m4a"),
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
            dateProcessed: processed
        )
        try await store.insert(r1)

        let oldest = await store.oldestUnprocessed()
        #expect(oldest == nil)
    }

    @Test("oldestUnprocessed returns nil for empty store")
    func oldestUnprocessedReturnsNilForEmpty() async {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)

        let oldest = await store.oldestUnprocessed()
        #expect(oldest == nil)
    }

    // MARK: - markProcessed

    @Test("markProcessed sets dateProcessed and persists to disk")
    func markProcessedSetsDatesAndPersists() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let record = makeRecord(path: "/memos/c.m4a")
        let processedDate = Date(timeIntervalSince1970: 1_700_099_000)

        try await store.insert(record)
        try await store.markProcessed(fileURL: record.fileURL, date: processedDate)

        // Reload from disk and verify
        let reloaded = JSONMemoStore(fileURL: storeURL)
        let oldest = await reloaded.oldestUnprocessed()
        #expect(oldest == nil) // should be nil since it's now processed

        let found = await reloaded.contains(fileURL: record.fileURL)
        #expect(found == true) // record still exists, just processed
    }

    @Test("markProcessed throws recordNotFound for unknown URL")
    func markProcessedThrowsForUnknownURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let missingURL = URL(fileURLWithPath: "/memos/nope.m4a")

        await #expect(throws: MemoStoreError.self) {
            try await store.markProcessed(fileURL: missingURL, date: Date())
        }
    }

    @Test("markProcessed throws recordNotFound with the correct URL")
    func markProcessedThrowsWithCorrectURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL)
        let missingURL = URL(fileURLWithPath: "/memos/nope.m4a")

        do {
            try await store.markProcessed(fileURL: missingURL, date: Date())
            Issue.record("Expected throw but succeeded")
        } catch MemoStoreError.recordNotFound(let url) {
            #expect(url.standardizedFileURL == missingURL.standardizedFileURL)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Persistence across instances

    @Test("Records written by one instance are readable by a new instance")
    func persistenceAcrossInstances() async throws {
        let storeURL = makeStoreURL()
        let r1 = makeRecord(path: "/memos/persist1.m4a", createdAt: 0)
        let r2 = makeRecord(path: "/memos/persist2.m4a", createdAt: 10)

        // Write with first instance
        let store1 = JSONMemoStore(fileURL: storeURL)
        try await store1.insert(r1)
        try await store1.insert(r2)

        // Read with a new instance
        let store2 = JSONMemoStore(fileURL: storeURL)
        let foundR1 = await store2.contains(fileURL: r1.fileURL)
        let foundR2 = await store2.contains(fileURL: r2.fileURL)

        #expect(foundR1 == true)
        #expect(foundR2 == true)

        let oldest = await store2.oldestUnprocessed()
        #expect(oldest?.fileURL == r1.fileURL)
    }

    // MARK: - Write failure

    @Test("insert throws writeFailed and leaves no partial state when file is unwritable")
    func insertThrowsWriteFailedForUnwritablePath() async throws {
        // Use a path inside a non-existent directory to force a write failure
        let badURL = URL(fileURLWithPath: "/nonexistent-dir/\(UUID().uuidString)/store.json")
        let store = JSONMemoStore(fileURL: badURL)
        let record = makeRecord(path: "/memos/d.m4a")

        await #expect(throws: MemoStoreError.self) {
            try await store.insert(record)
        }

        // In-memory state should be clean — contains should return false
        let found = await store.contains(fileURL: record.fileURL)
        #expect(found == false)
    }

    @Test("markProcessed throws writeFailed and rolls back dateProcessed when file is unwritable")
    func markProcessedRollsBackOnWriteFailure() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let writableURL = tempDir.appending(path: "\(UUID().uuidString).json")
        let writableStore = JSONMemoStore(fileURL: writableURL)
        let record = makeRecord(path: "/memos/rollback.m4a")
        try await writableStore.insert(record)

        // Copy data into a directory we'll make non-writable (atomic writes need dir access)
        let data = try Data(contentsOf: writableURL)
        let dir = tempDir.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeFile = dir.appending(path: "store.json")
        try data.write(to: storeFile)
        // Make the directory non-writable so atomic write fails (can't create temp file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: writableURL)
        }

        let store = JSONMemoStore(fileURL: storeFile)
        let processedDate = Date(timeIntervalSince1970: 2_000_000_000)

        await #expect(throws: MemoStoreError.self) {
            try await store.markProcessed(fileURL: record.fileURL, date: processedDate)
        }

        // dateProcessed should be rolled back — record should still be unprocessed
        let oldest = await store.oldestUnprocessed()
        #expect(oldest?.fileURL == record.fileURL)
        #expect(oldest?.dateProcessed == nil)
    }
}
