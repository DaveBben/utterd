# Transcription Pipeline (Stage 1) — Task Breakdown

**Plan**: [plan.md](plan.md)
**Date**: 2026-03-30
**Status**: Approved

---

## Key Decisions

- **Persistence: JSON file, not SQLite** — The datastore needs to survive restarts and store a small number of records. A JSON file read/written via `Codable` is the simplest approach with zero dependencies. SQLite was considered but adds unnecessary complexity for a single-user app processing a few memos per day. The project policy prohibits third-party dependencies for persistence.

- **Protocols and types in `Libraries/Sources/Core/`; SpeechAnalyzer impl in `Utterd/`** — All protocol definitions, data types, the JSON store, consumer, scheduler, and pipeline stage live in the local SPM package for fast `swift test`. The concrete `SpeechAnalyzerTranscriptionService` lives in the `Utterd/` app target because the `Speech` framework requires the macOS 26 SDK, which is not available during `swift build` against the package's macOS 15 deployment target. This mirrors the existing pattern where `RealFileSystemChecker` (app target) implements `FileSystemChecker` (library protocol).

- **Protocol abstraction for transcription** — `TranscriptionService` protocol with a concrete `SpeechAnalyzerTranscriptionService` requiring macOS 26+. Decided in the plan (OQ #2). The protocol lives in Core; the concrete implementation uses `@available(macOS 26, *)`.

- **`MemoRecord` uses `fileURL: URL`, not `filePath: String`** — For consistency with `VoiceMemoEvent.fileURL` and all other path handling in the codebase (`FileSystemChecker`, `DirectoryMonitor`), the record stores a `URL`. `URL` is `Codable`, so JSON persistence works identically. This eliminates `String`↔`URL` conversion bugs that could break deduplication. The `JSONMemoStore` should compare URLs via `.standardizedFileURL` to handle trailing slashes and encoding differences defensively.

- **`MemoStore` protocol is `async throws`** — Under Swift 6.2 strict concurrency, the concrete `JSONMemoStore` is implemented as a Swift `actor` for thread safety. Actor-isolated methods are inherently `async`, so the protocol methods must be `async throws` (or `async` for non-throwing ones). This is the clean concurrency design that avoids `@unchecked Sendable` hacks.

- **`MemoStoreError` enum for typed errors** — The `MemoStore` protocol defines a `MemoStoreError` enum with cases `.recordNotFound(URL)` and `.writeFailed(URL, underlying: Error)` so that callers (Tasks 5, 6a) can pattern-match on specific failure modes.

- **`MockMemoStore` is an `actor`** — Since `MemoStore` protocol methods are `async`, the mock must also be safe for async access. Making `MockMemoStore` an actor (rather than `@unchecked Sendable` class) avoids data races under Swift 6.2 strict concurrency. Tests access mock state via `await`. This differs from existing mocks (`MockFileSystemChecker`) whose protocol methods are synchronous.

- **Global lock is in-memory, not persisted** — The plan specifies the lock resets to `false` on every app launch (crash recovery). The lock is a `Bool` property on the scheduler, not a persisted field. The scheduler sets the lock before calling the handler, and exposes only `releaseLock()` for the handler to call on failure.

- **Scheduler uses `Clock` protocol for testability** — Following the established pattern in `VoiceMemoWatcher`, the scheduler accepts `any Clock<Duration>` so tests can use `ImmediateClock` instead of waiting real seconds. Lock-held skipping is logged at `info` level via the existing `WatcherLogger` protocol (no new log levels needed).

- **Pipeline result is emitted via callback, not stored** — The plan explicitly says transcripts are emitted, not persisted. The pipeline stage calls an async closure with the `TranscriptionResult`. Stage 2 will plug into this emission point.

- **SpeechAnalyzer uses `DictationTranscriber`** — The `Speech` framework offers `SpeechTranscriber` (short commands) and `DictationTranscriber` (natural speech with punctuation). Voice memos are conversational, so `DictationTranscriber` is the default choice. Note: if the implementer finds that `SpeechTranscriber` with `.offlineTranscription` preset produces better results at implementation time, it can be swapped behind the same protocol — the choice is internal to the concrete service.

- **TranscriptionPipelineStage is NOT `@MainActor`** — Transcription is CPU-bound and can take seconds to minutes for long memos. Running on `@MainActor` would freeze the menu bar app. The stage is a plain (non-isolated) class with `async` methods. The `transcribe` call runs on the cooperative thread pool. The scheduler (which IS `@MainActor`) calls `await stage.process()`, bridging naturally.

- **File copy before transcription** — The spec's data flow mandates "copied to a temp location → extraction from the copy" and CLAUDE.md says "only read from temporary copies." The pipeline stage copies the `.m4a` to a temp directory before calling `SpeechAnalyzer`, then cleans up the copy after. This protects against iCloud syncing mid-read.

- **Re-processing on restart is intentional before stage 2** — After successful transcription, the lock stays held and `dateProcessed` stays nil. If the app restarts before stage 2 exists, the lock resets and the same memo will be re-transcribed. This is a known, documented limitation of stage 1 in isolation. The `onResult` handler logs "Transcript emitted, awaiting stage 2" so the behavior is visible.

- **`MemoConsumer` injects a date provider** — The consumer accepts a `now: @Sendable () -> Date` parameter (defaulting to `{ Date() }`) so tests can inject a fixed date and assert exact `dateCreated` values instead of using "approximately now" window comparisons.

- **`PipelineController` accepts `any MemoStore`** — The controller uses protocol injection, not a concrete `JSONMemoStore` reference. The caller (Task 6b, `AppDelegate`) creates the concrete store and passes it in. This matches the dependency injection pattern used everywhere else in the codebase.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-01.1 (new memo → record created) | Task 2 |
| AC-01.2 (duplicate memo → no new record) | Task 2 |
| AC-01.3 (duplicate after restart → ignored) | Task 2 |
| AC-01.4 (datastore unwritable → error logged, no processing) | Task 2 |
| AC-02.1 (scheduler picks oldest unprocessed when lock free) | Task 4 |
| AC-02.2 (lock held → scheduler skips) | Task 4 |
| AC-02.3 (no unprocessed records → scheduler skips) | Task 4 |
| AC-02.4 (scheduler fires 30s after launch) | Task 4 (structural — sleep-before-poll is in the loop; timing verified by Clock injection) |
| AC-02.5 (crash recovery → lock resets) | Task 4 |
| AC-03.1 (lock set before transcription) | Task 4 |
| AC-03.2 (audio transcribed, result emitted) | Task 3, Task 5 |
| AC-03.3 (lock stays true, dateProcessed stays null after success) | Task 5, Task 6a |
| AC-03.4 (failure → logged, lock released, dateProcessed set) | Task 5, Task 6a |
| AC-03.5 (empty transcript → emitted as success) | Task 3, Task 5 |
| Edge: app crash during transcription | Task 4 (AC-02.5) |
| Edge: duplicate file events | Task 2 (AC-01.2) |
| Edge: file deleted before transcription | Task 5 (AC-03.4) |
| Edge: very long audio / lock prevents overlap | Task 4 (AC-02.2) |
| Edge: datastore unwritable | Task 2 (AC-01.4) |
| Edge: multiple rapid file events | Task 2, Task 4 |
| Edge: empty transcript | Task 3, Task 5 (AC-03.5) |
| Edge: iCloud file rename (conflict resolution) | Acknowledged V1 limitation — path-based dedup means renamed file treated as new. No task (deferred) |

---

## Tasks

### Task 0: Define Contracts & Interfaces

**Relevant Files:**
- `Libraries/Sources/Core/MemoRecord.swift` ← create
- `Libraries/Sources/Core/MemoStore.swift` ← create (protocol + error enum)
- `Libraries/Sources/Core/TranscriptionService.swift` ← create (protocol)
- `Libraries/Sources/Core/TranscriptionResult.swift` ← create
- `Libraries/Tests/CoreTests/MemoRecordTests.swift` ← create (round-trip Codable test)

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the input type that the consumer will receive from the watcher; `MemoRecord` is created from this. Note that it uses `fileURL: URL` — `MemoRecord` should use the same type for consistency
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — understand the `events() -> AsyncStream<VoiceMemoEvent>` API the consumer will subscribe to
- `Libraries/Sources/Core/FileSystemChecker.swift` — example of protocol-based abstraction pattern used in this codebase (protocol + mock for tests)
- `Libraries/Sources/Core/WatcherLogger.swift` — logging protocol pattern to follow

**Steps:**

1. [ ] Define `MemoRecord` struct — the persistent record for a voice memo:
   - `fileURL: URL` (unique identifier — full path to `.m4a` file, consistent with `VoiceMemoEvent.fileURL`)
   - `dateCreated: Date` (timestamp when the record was inserted)
   - `dateProcessed: Date?` (null while unprocessed; set on permanent failure or by stage 2)
   - Conforms to `Codable`, `Sendable`, `Equatable`
2. [ ] Define `MemoStoreError` enum in `MemoStore.swift`:
   - `.recordNotFound(URL)` — thrown by `markProcessed` when no record matches
   - `.writeFailed(URL, underlying: Error)` — thrown when JSON write to disk fails
   - Conforms to `Error`, `Sendable`
3. [ ] Define `MemoStore` protocol — the persistence interface (all methods are `async` to support actor-based implementations):
   - `func insert(_ record: MemoRecord) async throws` — inserts a new record; no-op if `fileURL` already exists
   - `func contains(fileURL: URL) async -> Bool` — checks if a record with this URL exists
   - `func oldestUnprocessed() async -> MemoRecord?` — returns the record with the oldest `dateCreated` where `dateProcessed` is nil
   - `func markProcessed(fileURL: URL, date: Date) async throws` — sets `dateProcessed` on the record matching this URL; throws `MemoStoreError.recordNotFound` if no match
   - Protocol conforms to `Sendable`
4. [ ] Define `TranscriptionResult` struct:
   - `transcript: String` (may be empty for silence/noise)
   - `fileURL: URL` (the source file that was transcribed)
   - Conforms to `Sendable`, `Equatable`
5. [ ] Define `TranscriptionService` protocol:
   - `func transcribe(fileURL: URL) async throws -> TranscriptionResult`
   - Protocol conforms to `Sendable`
6. [ ] Write a round-trip `Codable` test in `MemoRecordTests.swift`: create a `MemoRecord` with a file URL, `dateCreated`, and nil `dateProcessed`, encode to JSON, decode back, assert equality
7. [ ] Verify all files compile: `cd Libraries && swift build </dev/null 2>&1` and run the round-trip test

**Acceptance Criteria:**

- GIVEN the contracts files, WHEN compiled via `swift build`, THEN no errors exist
- GIVEN `MemoRecord` with a `fileURL`, `dateCreated`, and nil `dateProcessed`, WHEN encoded to JSON and decoded back, THEN the round-trip produces an equal value
- GIVEN `MemoStoreError.recordNotFound(url)`, WHEN matched in a catch block, THEN the URL is accessible for error reporting

**Do NOT:**
- Implement any concrete `MemoStore` (that is Task 1)
- Implement any concrete `TranscriptionService` (that is Task 3)
- Add any business logic — only define shapes and contracts
- Add a pipeline scheduler class yet — that is Task 4

---

### Task 1: Implement JSON File-Backed MemoStore

**Blocked By:** Task 0

**Relevant Files:**
- `Libraries/Sources/Core/JSONMemoStore.swift` ← create
- `Libraries/Tests/CoreTests/JSONMemoStoreTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/MemoStore.swift` — the `async` protocol and `MemoStoreError` enum this task implements (defined in Task 0)
- `Libraries/Sources/Core/MemoRecord.swift` — the record type stored, uses `fileURL: URL` (defined in Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — example of how existing test doubles are structured in this codebase

**Steps:**

1. [ ] Write failing tests for `JSONMemoStore` covering: insert new record, insert duplicate (no-op), contains for existing/missing URLs, oldestUnprocessed returns correct record, oldestUnprocessed returns nil when all processed, markProcessed updates the record, markProcessed with nonexistent URL throws `MemoStoreError.recordNotFound`, persistence across instances (write with one instance, read with a new instance pointing to the same file), and error handling when the file path is unwritable
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `JSONMemoStore`:
   a. Implement as a Swift `actor` conforming to `MemoStore`: accept a `fileURL: URL` for the JSON storage file location. On init, load existing records from the file if it exists (decode `[MemoRecord]`), otherwise start with an empty array
   b. Implement `insert(_:)`: check if `fileURL` already exists in the array (compare via `.standardizedFileURL` for robustness); if not, append and write the full array to disk as JSON. If the write fails, remove the appended record and throw `MemoStoreError.writeFailed`
   c. Implement `contains(fileURL:)`: linear search through the in-memory array by standardized file URL
   d. Implement `oldestUnprocessed()`: filter records where `dateProcessed` is nil, sort by `dateCreated` ascending, return first
   e. Implement `markProcessed(fileURL:date:)`: find the record by `fileURL`, set its `dateProcessed`, write to disk. If no record matches, throw `MemoStoreError.recordNotFound(fileURL)`
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN an empty store, WHEN `insert` is called with a new `MemoRecord`, THEN the record is persisted and `contains` returns `true` for that file URL
- GIVEN a store with an existing record for URL `/memos/a.m4a`, WHEN `insert` is called with the same URL, THEN no duplicate is created and no error is thrown
- GIVEN a store with 3 unprocessed records (created at T1, T2, T3), WHEN `oldestUnprocessed()` is called, THEN the record created at T1 is returned
- GIVEN a store with all records having non-nil `dateProcessed`, WHEN `oldestUnprocessed()` is called, THEN `nil` is returned
- GIVEN a store with records written to disk, WHEN a new `JSONMemoStore` instance is created pointing to the same file, THEN the records are loaded and accessible
- GIVEN a store where the storage file URL points to an unwritable location, WHEN `insert` is called, THEN `MemoStoreError.writeFailed` is thrown and no partial state is left in the in-memory array
- GIVEN a record with `dateProcessed` of nil, WHEN `markProcessed` is called with a matching URL, THEN the record's `dateProcessed` is set and the change is persisted to disk
- GIVEN no record matches the URL, WHEN `markProcessed` is called, THEN `MemoStoreError.recordNotFound` is thrown with the URL

**Do NOT:**
- Add the global processing lock to the store — the lock is in-memory runtime state (Task 4)
- Add any pruning/cleanup logic for old records — that is out of scope
- Use `@MainActor` — the store is a Swift `actor` with its own isolation

---

### Task 2: Implement MemoConsumer (Watcher → Store Bridge)

**Blocked By:** Task 0

**Relevant Files:**
- `Libraries/Sources/Core/MemoConsumer.swift` ← create
- `Libraries/Tests/CoreTests/MemoConsumerTests.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/MockMemoStore.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the `events()` API this consumer subscribes to; understand `AsyncStream<VoiceMemoEvent>` pattern
- `Libraries/Sources/Core/MemoStore.swift` — the `async` store protocol the consumer writes to (Task 0)
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the event type received from the watcher; note `fileURL: URL` maps directly to `MemoRecord.fileURL`
- `Libraries/Sources/Core/WatcherLogger.swift` — logging protocol to reuse for error reporting

**Steps:**

1. [ ] Create `MockMemoStore` as an `actor` implementing `MemoStore` protocol: tracks inserted records in an array, `contains` checks the array, `oldestUnprocessed` returns a configurable value, `markProcessed` records calls. Support a configurable `insertError: Error?` to simulate write failures. Using an actor (not `@unchecked Sendable` class) because the protocol methods are `async` — this avoids data races under strict concurrency. Tests access mock state via `await`
2. [ ] Write failing tests for `MemoConsumer` covering: new event creates a record in the store with matching `fileURL` and exact injected `dateCreated`, duplicate event (store already contains the URL) is silently ignored, store insert failure is logged and does not crash, multiple events in sequence are all recorded. **Test pattern**: create the stream via `AsyncStream.makeStream()`, yield test events via the continuation, then call `continuation.finish()` so that `consume()` returns. After `await consumer.consume(stream)` completes, assert mock state via `await mockStore.insertedRecords`
3. [ ] Run tests to verify they fail (confirm RED state)
4. [ ] Implement `MemoConsumer` as a `@MainActor` class: accepts `any MemoStore`, `any WatcherLogger`, and `now: @Sendable () -> Date = { Date() }` (injectable date provider for testability). Provide a `consume(_ stream: AsyncStream<VoiceMemoEvent>) async` method that iterates the stream. For each event: call `await store.contains(fileURL: event.fileURL)` — if true, skip. Otherwise create a `MemoRecord(fileURL: event.fileURL, dateCreated: now(), dateProcessed: nil)` and call `try await store.insert()`. Wrap insert in do/catch; on failure, log the error via the logger and continue
5. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a `VoiceMemoEvent` with URL `/memos/abc.m4a` and a date provider returning `2026-01-15T10:00:00Z`, WHEN the consumer processes it AND the store does not contain that URL, THEN `insert` is called with a `MemoRecord` whose `fileURL` matches, `dateCreated` equals `2026-01-15T10:00:00Z`, and `dateProcessed` is nil
- GIVEN a `VoiceMemoEvent` with URL `/memos/abc.m4a`, WHEN the consumer processes it AND the store already contains that URL, THEN `insert` is NOT called
- GIVEN a `VoiceMemoEvent`, WHEN the store's `insert` throws an error, THEN the error is logged via the logger and the consumer continues processing subsequent events without crashing
- GIVEN three events arrive in sequence, WHEN the consumer processes them, THEN all three are checked against the store and new ones are inserted

**Do NOT:**
- Start or manage the `VoiceMemoWatcher` — the consumer only receives a stream, it does not own the watcher
- Implement any scheduling or pipeline triggering — that is Task 4
- Interact with the global lock — the consumer only writes memo records

---

### Task 3: Implement MockTranscriptionService and SpeechAnalyzerTranscriptionService

**Blocked By:** Task 0

**Relevant Files:**
- `Utterd/Core/SpeechAnalyzerTranscriptionService.swift` ← create (app target, not library — requires Speech framework / macOS 26 SDK)
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptionService.swift` ← create
- `UtterdTests/SpeechAnalyzerTranscriptionServiceTests.swift` ← create
- `project.yml` ← modify (add `NSSpeechRecognitionUsageDescription` to `targets.Utterd.info.properties`)

**Context to Read First:**
- `Libraries/Sources/Core/TranscriptionService.swift` — the protocol this task implements (Task 0)
- `Libraries/Sources/Core/TranscriptionResult.swift` — the result type to return (Task 0)
- `Utterd/Core/RealFileSystemChecker.swift` — example of a concrete implementation in the app target that conforms to a library protocol
- `project.yml` — understand how Info.plist properties are configured. Look for the `info.properties` block under `targets.Utterd` — that is where `NSSpeechRecognitionUsageDescription` goes. Do NOT edit `Utterd/Resources/Info.plist` directly — it is generated by `xcodegen`
- Apple `SpeechAnalyzer` API docs (WWDC25 session 277) — the macOS 26+ speech-to-text API. Key classes: `DictationTranscriber`, `SpeechAnalyzer`. Flow: create transcriber + analyzer, run `analyzeSequence(from: AVAudioFile)`, collect results concurrently via `async let` on `transcriber.results`, finalize with `finalizeAndFinish(through: lastSample)`

**Steps:**

1. [ ] Create `MockTranscriptionService` in the library test target: stores a configurable `result: TranscriptionResult?` and `error: Error?`. When `transcribe` is called, throws the error if set, otherwise returns the result. Uses `@unchecked Sendable` + `nonisolated(unsafe)` pattern (protocol methods are `async` but the mock is simple enough for this pattern — it's only called from `@MainActor` test contexts)
2. [ ] Write failing tests: for `SpeechAnalyzerTranscriptionService`, test that calling `transcribe` with a nonexistent file URL throws an error, and that the type conforms to `TranscriptionService` (compilation check)
3. [ ] Run tests to verify they fail (confirm RED state)
4. [ ] Implement `SpeechAnalyzerTranscriptionService` in `Utterd/Core/`, gated with `@available(macOS 26, *)`, conforming to `TranscriptionService`. In `transcribe(fileURL:)`:
   a. Verify file exists at URL (throw if not)
   b. Create `AVAudioFile(forReading: fileURL)`
   c. Create `DictationTranscriber(locale: .current)` — verify initializer signature against SDK headers at implementation time, as Apple docs may not render the exact signature
   d. Use `async let` to concurrently collect results: `async let transcriptFuture = transcriber.results.reduce("") { text, result in text + result.text }`
   e. Create `SpeechAnalyzer(modules: [transcriber])` and call `let lastSample = try await analyzer.analyzeSequence(from: audioFile)`
   f. If `lastSample` is non-nil, call `try await analyzer.finalizeAndFinish(through: lastSample)`. If nil, call `await analyzer.cancelAndFinishNow()`
   g. Await the transcript: `let transcript = try await transcriptFuture`
   h. Return `TranscriptionResult(transcript: transcript, fileURL: fileURL)`. Empty text is returned as-is (not an error)
5. [ ] Add `NSSpeechRecognitionUsageDescription` to the `info.properties` block inside `project.yml` (under `targets.Utterd.info.properties`) with value "Utterd uses speech recognition to transcribe your voice memos." Do NOT edit `Utterd/Resources/Info.plist` directly — it is generated and changes will be overwritten by `xcodegen generate`
6. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a file URL that does not exist on disk, WHEN `SpeechAnalyzerTranscriptionService.transcribe` is called, THEN an error is thrown before attempting speech analysis
- GIVEN the `SpeechAnalyzerTranscriptionService` type, WHEN compiled via `xcodebuild`, THEN it compiles without errors and conforms to `TranscriptionService`
- GIVEN `NSSpeechRecognitionUsageDescription` is added to `project.yml`'s `targets.Utterd.info.properties`, WHEN `xcodegen generate` is run, THEN the generated Info.plist contains `NSSpeechRecognitionUsageDescription`

**Do NOT:**
- Test actual audio transcription in unit tests — `SpeechAnalyzer` requires real hardware and audio files; the mock covers pipeline integration testing
- Add retry logic — the plan explicitly says each memo is attempted once
- Add format conversion — `SpeechAnalyzer`/`AVAudioFile` can process `.m4a` directly
- Place `SpeechAnalyzerTranscriptionService` in the `Libraries/` SPM package — the `Speech` framework is not available during `swift build` against the macOS 15 SDK
- Test `MockTranscriptionService` behavior in dedicated tests — mock correctness is verified through its usage in Task 5's pipeline stage tests

---

### Task 4: Implement PipelineScheduler

**Blocked By:** Task 0, Task 2

**Relevant Files:**
- `Libraries/Sources/Core/PipelineScheduler.swift` ← create
- `Libraries/Tests/CoreTests/PipelineSchedulerTests.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/ImmediateClock.swift` ← already exists, reuse

**Context to Read First:**
- `Libraries/Sources/Core/MemoStore.swift` — the `async` store protocol the scheduler queries for unprocessed records (Task 0)
- `Libraries/Sources/Core/MemoRecord.swift` — the record type returned by `oldestUnprocessed()` (Task 0)
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — reference for the `Clock`-based testability pattern (lines 14, 30, 122) and the `Task`-based background loop pattern (lines 57-79)
- `Libraries/Sources/Core/WatcherLogger.swift` — logging protocol for scheduler lifecycle messages
- `Libraries/Tests/CoreTests/Mocks/ImmediateClock.swift` — the clock mock to reuse in scheduler tests
- `Libraries/Tests/CoreTests/Mocks/MockMemoStore.swift` — the actor-based store mock created in Task 2

**Steps:**

1. [ ] Write failing tests. **Critical test infrastructure**: with `ImmediateClock`, the scheduler loop spins as fast as cooperative scheduling allows. Create a test helper: a handler closure that records each call (record + call count), and calls `scheduler.stop()` after a configurable number of invocations to prevent runaway loops. Each test should specify the exact handler behavior:
   - "handler stops scheduler on first call" → assert handler was called exactly once with the expected record
   - "handler is never called" → for lock-held and no-records tests, configure store to return nil / set lock, let one cycle complete via a short `Task.sleep(for: .milliseconds(50))`, then stop and assert zero handler calls
   Tests to write: scheduler calls handler with the oldest unprocessed record when lock is free (handler stops on first call); scheduler skips when lock is held (logs "Lock held, skipping"); scheduler skips when no unprocessed records exist; lock resets to false on `start()` (crash recovery); scheduler runs repeatedly (handler stops after 3 calls, assert 3 records processed); `stop()` ends the scheduling loop; `releaseLock()` sets lock to false; handler returns `true` → lock stays held, next cycle logs "Lock held, skipping"; handler returns `false` → lock released, next record eligible
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `PipelineScheduler` as a `@MainActor` class: accepts `any MemoStore`, `any Clock<Duration>`, polling interval (`Duration`, default `.seconds(30)`), `any WatcherLogger`, and a pipeline handler `@Sendable (MemoRecord) async -> Bool` (returns true for success, false for failure). Holds `private var isLocked: Bool = false` and `private var schedulerTask: Task<Void, Never>?`
4. [ ] Implement `start()`: set `isLocked = false` (crash recovery — AC-02.5), log "Scheduler started", launch a `Task` that loops: sleep for the polling interval, check `Task.isCancelled` (exit if so), check `isLocked` — if true, log "Lock held, skipping" at info level and continue. Call `await store.oldestUnprocessed()` — if nil, continue. Otherwise set `isLocked = true`, log "Processing: [fileURL]" at info level, call the handler. If handler returns `false`, call `releaseLock()` (permanent failure — caller signals lock release)
5. [ ] Implement `stop()`: cancel the scheduler task, set it to nil, log "Scheduler stopped"
6. [ ] Implement `releaseLock()`: sets `isLocked = false`. This is the only public lock mutation — the scheduler sets the lock internally before calling the handler, and the handler's return value determines whether `releaseLock()` is called
7. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN one unprocessed record in the store AND the lock is free, WHEN the scheduler fires, THEN `isLocked` is set to `true` before the handler is called, and the handler receives that record
- GIVEN the lock is true, WHEN the scheduler fires, THEN the handler is NOT called, "Lock held, skipping" is logged at info level, and the scheduler waits for the next cycle
- GIVEN no unprocessed records in the store, WHEN the scheduler fires, THEN no action is taken
- GIVEN the app previously crashed (lock was implicitly true), WHEN `start()` is called, THEN the lock is reset to false and unprocessed records become eligible
- GIVEN 3 unprocessed records (created at T1, T2, T3), WHEN the scheduler fires, THEN the record with the oldest `dateCreated` (T1) is selected
- GIVEN the scheduler is running, WHEN `stop()` is called, THEN the scheduling loop ends and no further handler calls are made
- GIVEN the handler returns `false`, WHEN the scheduler loop continues, THEN `releaseLock()` is called and the lock becomes free for the next cycle
- GIVEN the handler returns `true` (success), WHEN the next scheduler cycle fires, THEN the lock is still held and the scheduler logs "Lock held, skipping"

**Do NOT:**
- Implement transcription logic inside the scheduler — the scheduler calls a handler closure; transcription is wired in Task 6a
- Persist the lock to disk — it is in-memory and resets on launch
- Add smart enable/disable based on queue state — the plan decided the scheduler always runs
- Expose `acquireLock()` — the scheduler sets the lock internally before calling the handler; only `releaseLock()` is public

---

### Task 5: Implement TranscriptionPipelineStage (Orchestration)

**Blocked By:** Task 2, Task 3, Task 4

**Relevant Files:**
- `Libraries/Sources/Core/TranscriptionPipelineStage.swift` ← create
- `Libraries/Tests/CoreTests/TranscriptionPipelineStageTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/TranscriptionService.swift` — the transcription protocol called by this stage (Task 0)
- `Libraries/Sources/Core/MemoStore.swift` — the `async` store protocol and `MemoStoreError` for marking permanent failures (Task 0)
- `Libraries/Sources/Core/MemoRecord.swift` — the record type passed in from the scheduler; uses `fileURL: URL` (Task 0)
- `Libraries/Sources/Core/TranscriptionResult.swift` — the result type emitted downstream (Task 0)
- `Libraries/Sources/Core/WatcherLogger.swift` — logging protocol for error reporting
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptionService.swift` — mock for controlling transcription outcomes (Task 3)
- `Libraries/Tests/CoreTests/Mocks/MockMemoStore.swift` — actor-based mock for verifying store interactions (Task 2)

**Steps:**

1. [ ] Write failing tests covering: successful transcription emits result via callback and returns `true`; transcription failure logs error, calls `markProcessed` with current date, and returns `false`; empty transcript is emitted as success (returns `true`); the `onResult` callback receives the correct `TranscriptionResult` with transcript text and file URL; on failure, `onResult` is NOT called; the stage copies the file to a temp location before transcribing and cleans up after. **Test pattern for file copy/cleanup**: create a real `.m4a` file in the test's temp directory (using `FileManager.default.createFile`), configure `MockTranscriptionService` to succeed or fail, call `process()`, then assert the temp copy is cleaned up by checking `FileManager.default.fileExists` — no `FileManager` abstraction needed for V1
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `TranscriptionPipelineStage` as a plain class (NOT `@MainActor` — transcription is CPU-bound and must not block the main thread): accepts `any TranscriptionService`, `any MemoStore`, `any WatcherLogger`, and `onResult: @Sendable (TranscriptionResult) async -> Void` callback
4. [ ] Implement `process(_ record: MemoRecord) async -> Bool`:
   a. Copy the `.m4a` file from `record.fileURL` to a temp directory (`FileManager.default.temporaryDirectory` + UUID filename) to avoid reading from the iCloud sync directory directly
   b. Call `await transcriptionService.transcribe(fileURL: tempURL)` inside a do/catch
   c. On success: create a `TranscriptionResult(transcript: text, fileURL: record.fileURL)` (use original URL, not temp), call `await onResult(result)`, clean up temp file, return `true`
   d. On failure (any error including file-not-found or copy failure): log the error, call `try? await store.markProcessed(fileURL: record.fileURL, date: Date())`, clean up temp file if it exists, return `false`
5. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a `MemoRecord` with a valid file URL, WHEN `process` is called AND transcription succeeds with text "Buy groceries", THEN `onResult` is called with a `TranscriptionResult` containing transcript "Buy groceries" and the original file URL (not temp), and the method returns `true`
- GIVEN a `MemoRecord` with a valid file URL, WHEN `process` is called AND transcription succeeds with empty string "", THEN `onResult` is called with a `TranscriptionResult` containing empty transcript, and the method returns `true` (empty transcript is a successful result per AC-03.5)
- GIVEN a `MemoRecord` whose file does not exist, WHEN `process` is called AND the copy fails, THEN the error is logged, `markProcessed` is called on the store with the current date, `onResult` is NOT called, and the method returns `false`
- GIVEN a `MemoRecord`, WHEN `process` is called AND transcription throws any error, THEN the error is logged, `markProcessed` is called (permanent failure), `onResult` is NOT called, and the method returns `false`
- GIVEN a successful or failed transcription, WHEN `process` completes, THEN no temp file remains on disk

**Do NOT:**
- Acquire or release the global lock — the scheduler manages the lock (sets it before calling the handler, releases it when this method returns `false`)
- Set `dateProcessed` on successful transcription — that is stage 2's responsibility
- Add retry logic — each memo is attempted once per the plan
- Store the transcript anywhere — it is emitted via callback only
- Use `@MainActor` — transcription is CPU-bound; this class must not block the main thread

---

### Task 6a: Implement PipelineController

**Blocked By:** Task 1, Task 2, Task 4, Task 5

**Relevant Files:**
- `Libraries/Sources/Core/PipelineController.swift` ← create
- `Libraries/Tests/CoreTests/PipelineControllerTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the watcher provides the event stream via `events()`
- `Libraries/Sources/Core/MemoConsumer.swift` — bridges watcher events to the store (Task 2)
- `Libraries/Sources/Core/PipelineScheduler.swift` — drives processing on a timer (Task 4); exposes `releaseLock()` and accepts a handler returning `Bool`
- `Libraries/Sources/Core/TranscriptionPipelineStage.swift` — transcribes memos, returns `Bool` (Task 5)
- `Libraries/Sources/Core/WatcherLogger.swift` — logging protocol

**Steps:**

1. [ ] Write failing tests for `PipelineController`. **Test approach**: inject a `MockMemoStore` (seeded with a record), a `MockTranscriptionService` (configured to return a result), a `MockWatcherLogger`, and `ImmediateClock`. Create a `PipelineController`, call `start()`, and verify via the mocks that: the scheduler handler calls `stage.process(record)`, `MockTranscriptionService.transcribe` is called, `onResult` logs the expected message. Test lock release: configure `MockTranscriptionService` to throw, verify `scheduler.releaseLock()` is called (lock becomes free). Test lock hold: configure success, verify lock stays held
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `PipelineController` as a `@MainActor` class: initializer accepts `store: any MemoStore`, `transcriptionService: any TranscriptionService`, `watcherStream: AsyncStream<VoiceMemoEvent>`, `logger: any WatcherLogger`, and optionally `clock: any Clock<Duration>` (for test injection, defaults to `ContinuousClock()`). Holds references to the consumer, scheduler, and pipeline stage. Also holds a `consumerTask: Task<Void, Never>?` for the consumer's long-running stream iteration
4. [ ] Implement `start() async`: create the pipeline stage with an `onResult` handler that logs "Transcript emitted for [fileURL], awaiting stage 2". Create the scheduler with a handler that calls `await stage.process(record)` and if the result is `false`, calls `scheduler.releaseLock()`. Create the consumer and launch `consume(watcherStream)` as a background `Task` (stored in `consumerTask`). Call `await scheduler.start()`
5. [ ] Implement `stop()`: call `scheduler.stop()`, cancel `consumerTask`
6. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a `PipelineController` is started with a store containing one unprocessed record, WHEN the scheduler fires, THEN `TranscriptionPipelineStage.process()` is called with that record and the transcription service's `transcribe` is invoked
- GIVEN `process()` returns `false` (permanent failure), WHEN the handler completes, THEN `scheduler.releaseLock()` is called and the lock becomes free
- GIVEN `process()` returns `true` (success), WHEN the handler completes, THEN the lock remains held (stage 2 will release it)
- GIVEN a successful transcription, WHEN `onResult` is called, THEN a log message containing "awaiting stage 2" is emitted
- GIVEN `stop()` is called, WHEN the scheduler and consumer are running, THEN both are stopped

**Do NOT:**
- Implement stage 2 (LLM classification/routing) — the `onResult` handler logs and returns
- Create the `VoiceMemoWatcher` — it is created elsewhere; the controller receives its event stream
- Add UI changes to the menu bar — explicitly out of scope
- Hardcode `JSONMemoStore` — the controller accepts `any MemoStore` for testability

---

### Task 6b: Wire PipelineController into App Lifecycle

**Blocked By:** Task 6a

**Relevant Files:**
- `Utterd/App/AppDelegate.swift` ← modify (add pipeline startup and teardown)
- `UtterdTests/AppDelegatePipelineTests.swift` ← create

**Context to Read First:**
- `Utterd/App/AppDelegate.swift` — understand current app lifecycle setup and permission gate. Note: `applicationWillTerminate` does not currently exist and must be added. The guard `if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }` skips permission gate in tests
- `UtterdTests/PermissionGateTests.swift` — example of how `AppDelegate` behavior is tested in this codebase (extract testable functions, test them directly)
- `Libraries/Sources/Core/PipelineController.swift` — the controller to instantiate (Task 6a)
- `Utterd/Core/RealFileSystemChecker.swift` — example of how app target creates concrete implementations
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — understand how to create a watcher and get its event stream

**Steps:**

1. [ ] Write failing tests. **Test approach**: follow the `evaluatePermissionGate()` pattern from `PermissionGateTests.swift` — extract the pipeline startup logic into a testable function (e.g., `func createPipelineController(...)`) that can be tested independently of `AppDelegate` lifecycle methods. Test: on macOS 26+ the function creates a `PipelineController` with the correct store path and transcription service; on macOS < 26 it returns nil and logs a warning; Application Support directory is created if missing
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Modify `AppDelegate.swift`: add a `private var pipelineController: PipelineController?` property. After the permission gate passes in `applicationDidFinishLaunching`, create a `VoiceMemoWatcher` (or reuse if one already exists), check `if #available(macOS 26, *)` — if available, create a `SpeechAnalyzerTranscriptionService`, determine the store file path (`~/Library/Application Support/com.bennett.Utterd/memo-store.json` — create directory with `FileManager.default.createDirectory(withIntermediateDirectories: true)` if needed), create `JSONMemoStore`, instantiate `PipelineController(store:transcriptionService:watcherStream:logger:)`, and call `await start()`. If macOS < 26, log a warning "Transcription pipeline requires macOS 26+" and do not start the pipeline
4. [ ] Add `applicationWillTerminate(_:)` to `AppDelegate`: call `pipelineController?.stop()`
5. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN the app launches on macOS 26+ with voice memo directory access, WHEN `applicationDidFinishLaunching` completes, THEN a `PipelineController` is created with `JSONMemoStore` and `SpeechAnalyzerTranscriptionService`, and `start()` is called
- GIVEN the app launches on macOS < 26, WHEN `applicationDidFinishLaunching` completes, THEN a warning "Transcription pipeline requires macOS 26+" is logged and the pipeline is NOT started
- GIVEN the app is terminating, WHEN `applicationWillTerminate` fires, THEN `stop()` is called on the pipeline controller
- GIVEN the Application Support directory `com.bennett.Utterd` does not exist, WHEN the pipeline starts, THEN the directory is created before the store file is opened

**Do NOT:**
- Implement stage 2 (LLM classification/routing)
- Add UI changes to the menu bar — explicitly out of scope
- Add speech recognition permission prompting — the system handles the prompt automatically when `SpeechAnalyzer` is first used, and `NSSpeechRecognitionUsageDescription` was added in Task 3
