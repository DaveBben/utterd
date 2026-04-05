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
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/a.m4a")

        try await store.insert(record)

        let found = await store.contains(fileURL: record.fileURL)
        #expect(found == true)
    }

    @Test("Insert duplicate: no-op, no error, no duplicate record")
    func insertDuplicateIsNoOp() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/a.m4a")

        try await store.insert(record)
        try await store.insert(record) // second insert — should be silent no-op

        // Reload from disk and verify only one record
        let reloaded = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
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
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let url = URL(fileURLWithPath: "/memos/missing.m4a")

        let found = await store.contains(fileURL: url)
        #expect(found == false)
    }

    @Test("contains returns true for existing URL")
    func containsReturnsTrueForExistingURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/b.m4a")

        try await store.insert(record)

        let found = await store.contains(fileURL: record.fileURL)
        #expect(found == true)
    }

    // MARK: - oldestUnprocessed

    @Test("oldestUnprocessed returns record created earliest")
    func oldestUnprocessedReturnsEarliest() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())

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
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
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
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())

        let oldest = await store.oldestUnprocessed()
        #expect(oldest == nil)
    }

    // MARK: - markProcessed

    @Test("markProcessed sets dateProcessed and persists to disk")
    func markProcessedSetsDatesAndPersists() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/c.m4a")
        let processedDate = Date(timeIntervalSince1970: 1_700_099_000)

        try await store.insert(record)
        try await store.markProcessed(fileURL: record.fileURL, date: processedDate)

        // Reload from disk and verify
        let reloaded = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let oldest = await reloaded.oldestUnprocessed()
        #expect(oldest == nil) // should be nil since it's now processed

        let found = await reloaded.contains(fileURL: record.fileURL)
        #expect(found == true) // record still exists, just processed
    }

    @Test("markProcessed throws recordNotFound for unknown URL")
    func markProcessedThrowsForUnknownURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let missingURL = URL(fileURLWithPath: "/memos/nope.m4a")

        await #expect(throws: MemoStoreError.self) {
            try await store.markProcessed(fileURL: missingURL, date: Date())
        }
    }

    @Test("markProcessed throws recordNotFound with the correct URL")
    func markProcessedThrowsWithCorrectURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
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
        let store1 = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        try await store1.insert(r1)
        try await store1.insert(r2)

        // Read with a new instance
        let store2 = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let foundR1 = await store2.contains(fileURL: r1.fileURL)
        let foundR2 = await store2.contains(fileURL: r2.fileURL)

        #expect(foundR1 == true)
        #expect(foundR2 == true)

        let oldest = await store2.oldestUnprocessed()
        #expect(oldest?.fileURL == r1.fileURL)
    }

    // MARK: - mostRecentlyProcessed

    @Test("mostRecentlyProcessed returns nil for empty store")
    func mostRecentlyProcessedReturnsNilForEmpty() async {
        let store = JSONMemoStore(fileURL: makeStoreURL(), logger: MockWatcherLogger())

        let result = await store.mostRecentlyProcessed()
        #expect(result == nil)
    }

    @Test("mostRecentlyProcessed returns nil when all records are unprocessed")
    func mostRecentlyProcessedReturnsNilWhenAllUnprocessed() async throws {
        let store = JSONMemoStore(fileURL: makeStoreURL(), logger: MockWatcherLogger())

        try await store.insert(makeRecord(path: "/memos/u1.m4a", createdAt: 100))
        try await store.insert(makeRecord(path: "/memos/u2.m4a", createdAt: 200))

        let result = await store.mostRecentlyProcessed()
        #expect(result == nil)
    }

    @Test("mostRecentlyProcessed returns the single processed record")
    func mostRecentlyProcessedReturnsSingleProcessedRecord() async throws {
        let store = JSONMemoStore(fileURL: makeStoreURL(), logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/p1.m4a", createdAt: 0)
        let processedDate = Date(timeIntervalSince1970: 1_700_050_000)

        try await store.insert(record)
        try await store.markProcessed(fileURL: record.fileURL, date: processedDate)

        let result = await store.mostRecentlyProcessed()
        #expect(result?.fileURL == record.fileURL)
        #expect(result?.dateProcessed == processedDate)
    }

    @Test("mostRecentlyProcessed returns the record with the latest dateProcessed")
    func mostRecentlyProcessedReturnsLatestAmongMultiple() async throws {
        let store = JSONMemoStore(fileURL: makeStoreURL(), logger: MockWatcherLogger())

        let r1 = makeRecord(path: "/memos/q1.m4a", createdAt: 0)
        let r2 = makeRecord(path: "/memos/q2.m4a", createdAt: 10)
        let r3 = makeRecord(path: "/memos/q3.m4a", createdAt: 20)

        let date10 = Date(timeIntervalSince1970: 1_700_010_000)
        let date11 = Date(timeIntervalSince1970: 1_700_011_000)
        let date12 = Date(timeIntervalSince1970: 1_700_012_000)

        try await store.insert(r1)
        try await store.insert(r2)
        try await store.insert(r3)
        try await store.markProcessed(fileURL: r1.fileURL, date: date10)
        try await store.markProcessed(fileURL: r2.fileURL, date: date11)
        try await store.markProcessed(fileURL: r3.fileURL, date: date12)

        let result = await store.mostRecentlyProcessed()
        #expect(result?.fileURL == r3.fileURL)
    }

    @Test("mostRecentlyProcessed ignores unprocessed records")
    func mostRecentlyProcessedIgnoresUnprocessed() async throws {
        let store = JSONMemoStore(fileURL: makeStoreURL(), logger: MockWatcherLogger())

        let processed = makeRecord(path: "/memos/processed.m4a", createdAt: 0)
        let unprocessed = makeRecord(path: "/memos/unprocessed.m4a", createdAt: 10)
        let processedDate = Date(timeIntervalSince1970: 1_700_010_000)

        try await store.insert(processed)
        try await store.insert(unprocessed)
        try await store.markProcessed(fileURL: processed.fileURL, date: processedDate)

        let result = await store.mostRecentlyProcessed()
        #expect(result?.fileURL == processed.fileURL)
    }

    // MARK: - Corruption resilience

    @Test("Init with corrupt file starts empty and creates backup")
    func initWithCorruptFileCreatesBackupAndStartsEmpty() async throws {
        let storeURL = makeStoreURL()
        try Data("not valid json".utf8).write(to: storeURL)

        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let oldest = await store.oldestUnprocessed()
        #expect(oldest == nil)

        let backupURL = storeURL.appendingPathExtension("corrupt-backup")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        let backupData = try Data(contentsOf: backupURL)
        #expect(String(data: backupData, encoding: .utf8) == "not valid json")

        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: backupURL)
    }

    @Test("Init with missing file starts empty")
    func initWithMissingFileStartsEmpty() async {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let oldest = await store.oldestUnprocessed()
        #expect(oldest == nil)
    }

    // MARK: - Write failure

    @Test("insert throws writeFailed and leaves no partial state when file is unwritable")
    func insertThrowsWriteFailedForUnwritablePath() async throws {
        // Use a path inside a non-existent directory to force a write failure
        let badURL = URL(fileURLWithPath: "/nonexistent-dir/\(UUID().uuidString)/store.json")
        let store = JSONMemoStore(fileURL: badURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/d.m4a")

        await #expect(throws: MemoStoreError.self) {
            try await store.insert(record)
        }

        // In-memory state should be clean — contains should return false
        let found = await store.contains(fileURL: record.fileURL)
        #expect(found == false)
    }

    // MARK: - markFailed

    @Test("markFailed sets dateFailed and failureReason and persists to disk")
    func markFailedSetsFieldsAndPersists() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/fail.m4a")
        let failDate = Date(timeIntervalSince1970: 1_700_099_000)

        try await store.insert(record)
        try await store.markFailed(fileURL: record.fileURL, reason: "transcription error", date: failDate)

        let reloaded = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let reloadedRecord = await reloaded.contains(fileURL: record.fileURL)
        #expect(reloadedRecord == true)

        // Verify via allUnprocessed — failed record should NOT be in this list
        let unprocessed = await reloaded.allUnprocessed()
        #expect(unprocessed.isEmpty)

        // Verify fields by checking oldestUnprocessed returns nil (AC-3.6)
        let oldest = await reloaded.oldestUnprocessed()
        #expect(oldest == nil)
    }

    @Test("markFailed persists dateFailed and failureReason (AC-3.5)")
    func markFailedPersistenceAcrossInstances() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/fail2.m4a")
        let failDate = Date(timeIntervalSince1970: 1_700_099_000)
        let reason = "some failure reason"

        try await store.insert(record)
        try await store.markFailed(fileURL: record.fileURL, reason: reason, date: failDate)

        // Reload and read back the raw record to verify fields
        let reloaded = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        // allUnprocessed excludes failed, so check via contains + oldestUnprocessed
        let oldest = await reloaded.oldestUnprocessed()
        #expect(oldest == nil) // failed record is excluded

        // The record is still in the store (contains returns true)
        let found = await reloaded.contains(fileURL: record.fileURL)
        #expect(found == true)

        // To verify dateFailed and failureReason directly, check the raw JSON
        let data = try Data(contentsOf: storeURL)
        let decoded = try JSONDecoder().decode([MemoRecord].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].dateFailed == failDate)
        #expect(decoded[0].failureReason == reason)
    }

    @Test("oldestUnprocessed excludes failed records (AC-3.6)")
    func oldestUnprocessedExcludesFailedRecords() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/failed.m4a")

        try await store.insert(record)
        try await store.markFailed(fileURL: record.fileURL, reason: "error", date: Date())

        let oldest = await store.oldestUnprocessed()
        #expect(oldest == nil)
    }

    @Test("markFailed throws recordNotFound for unknown URL")
    func markFailedThrowsForUnknownURL() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())
        let missingURL = URL(fileURLWithPath: "/memos/nope.m4a")

        await #expect(throws: MemoStoreError.self) {
            try await store.markFailed(fileURL: missingURL, reason: "err", date: Date())
        }
    }

    @Test("markFailed throws writeFailed and rolls back fields when file is unwritable")
    func markFailedRollsBackOnWriteFailure() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let writableURL = tempDir.appending(path: "\(UUID().uuidString).json")
        let writableStore = JSONMemoStore(fileURL: writableURL, logger: MockWatcherLogger())
        let record = makeRecord(path: "/memos/rollback-failed.m4a")
        try await writableStore.insert(record)

        let data = try Data(contentsOf: writableURL)
        let dir = tempDir.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeFile = dir.appending(path: "store.json")
        try data.write(to: storeFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: writableURL)
        }

        let store = JSONMemoStore(fileURL: storeFile, logger: MockWatcherLogger())

        await #expect(throws: MemoStoreError.self) {
            try await store.markFailed(fileURL: record.fileURL, reason: "err", date: Date())
        }

        // Fields should be rolled back — record should still appear in oldestUnprocessed
        let oldest = await store.oldestUnprocessed()
        #expect(oldest?.fileURL == record.fileURL)
        #expect(oldest?.dateFailed == nil)
        #expect(oldest?.failureReason == nil)
    }

    // MARK: - allUnprocessed

    @Test("allUnprocessed returns only unprocessed and non-failed records in dateCreated order")
    func allUnprocessedReturnsOnlyUnprocessedRecordsInOrder() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())

        let rProcessed = makeRecord(path: "/memos/processed.m4a", createdAt: 100)
        let rFailed = makeRecord(path: "/memos/failed.m4a", createdAt: 200)
        let rUnprocessed = makeRecord(path: "/memos/unprocessed.m4a", createdAt: 300)

        try await store.insert(rProcessed)
        try await store.insert(rFailed)
        try await store.insert(rUnprocessed)

        try await store.markProcessed(fileURL: rProcessed.fileURL, date: Date(timeIntervalSince1970: 1_700_099_000))
        try await store.markFailed(fileURL: rFailed.fileURL, reason: "err", date: Date(timeIntervalSince1970: 1_700_099_001))

        let result = await store.allUnprocessed()
        #expect(result.count == 1)
        #expect(result[0].fileURL == rUnprocessed.fileURL)
    }

    @Test("allUnprocessed returns multiple unprocessed records ordered by dateCreated ascending")
    func allUnprocessedReturnsMultipleInDateOrder() async throws {
        let storeURL = makeStoreURL()
        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())

        let r300 = makeRecord(path: "/memos/r300.m4a", createdAt: 300)
        let r100 = makeRecord(path: "/memos/r100.m4a", createdAt: 100)
        let r200 = makeRecord(path: "/memos/r200.m4a", createdAt: 200)

        try await store.insert(r300)
        try await store.insert(r100)
        try await store.insert(r200)

        let result = await store.allUnprocessed()
        #expect(result.count == 3)
        #expect(result[0].fileURL == r100.fileURL)
        #expect(result[1].fileURL == r200.fileURL)
        #expect(result[2].fileURL == r300.fileURL)
    }

    // MARK: - Backward compatibility

    @Test("JSON records without dateFailed/failureReason fields decode with nil failure fields (AC-3.9)")
    func backwardCompatibilityDecodesOldRecordsWithoutFailureFields() async throws {
        let storeURL = makeStoreURL()

        // Hardcoded JSON representing records from an older version without failure fields.
        // Dates are seconds since the Apple reference date (2001-01-01), which is what
        // JSONEncoder's default .deferredToDate strategy uses. Values:
        //   dateCreated  = 1_700_000_000 epoch → 721_692_800 reference
        //   dateProcessed = 1_700_099_000 epoch → 721_791_800 reference
        //   dateCreated2 = 1_700_001_000 epoch → 721_693_800 reference
        let oldJSON = """
        [
          {
            "fileURL": "file:///memos/old1.m4a",
            "dateCreated": 721692800,
            "dateProcessed": 721791800
          },
          {
            "fileURL": "file:///memos/old2.m4a",
            "dateCreated": 721693800
          }
        ]
        """
        try Data(oldJSON.utf8).write(to: storeURL)

        let store = JSONMemoStore(fileURL: storeURL, logger: MockWatcherLogger())

        // Both records should decode — no crash
        let found1 = await store.contains(fileURL: URL(string: "file:///memos/old1.m4a")!)
        let found2 = await store.contains(fileURL: URL(string: "file:///memos/old2.m4a")!)
        #expect(found1 == true)
        #expect(found2 == true)

        // Unprocessed should return only old2 (old1 has dateProcessed set)
        let unprocessed = await store.allUnprocessed()
        #expect(unprocessed.count == 1)
        #expect(unprocessed[0].fileURL == URL(string: "file:///memos/old2.m4a")!)
        #expect(unprocessed[0].dateFailed == nil)
        #expect(unprocessed[0].failureReason == nil)

        // old1's dateProcessed is preserved
        let oldest = await store.oldestUnprocessed()
        #expect(oldest?.fileURL == URL(string: "file:///memos/old2.m4a")!)

        // Verify old1 dateProcessed preserved via raw decode
        let data = try Data(contentsOf: storeURL)
        let decoded = try JSONDecoder().decode([MemoRecord].self, from: data)
        let old1 = decoded.first(where: { $0.fileURL == URL(string: "file:///memos/old1.m4a")! })
        // 721_791_800 seconds from reference date = 1_700_099_000 seconds from epoch
        #expect(old1?.dateProcessed == Date(timeIntervalSinceReferenceDate: 721_791_800))
        #expect(old1?.dateFailed == nil)
        #expect(old1?.failureReason == nil)
    }

    @Test("markProcessed throws writeFailed and rolls back dateProcessed when file is unwritable")
    func markProcessedRollsBackOnWriteFailure() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let writableURL = tempDir.appending(path: "\(UUID().uuidString).json")
        let writableStore = JSONMemoStore(fileURL: writableURL, logger: MockWatcherLogger())
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

        let store = JSONMemoStore(fileURL: storeFile, logger: MockWatcherLogger())
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
