# Tasks: Immediate Queue-Based Pipeline

**Plan**: [plan.md](plan.md)
**Status**: Approved
**Created**: 2026-04-04

---

## Key Decisions

- The queue is built on `AsyncStream` — a `for await` loop gives natural sequential, immediate processing
- `MemoRecord` gains optional `dateFailed: Date?` and `failureReason: String?` fields (backward-compatible via `Codable` defaults)
- `MemoStore` protocol gains `markFailed(fileURL:reason:date:)` and `allUnprocessed() -> [MemoRecord]` (for startup drain)
- `oldestUnprocessed()` stays on the protocol but its filter is updated to exclude failed records
- `NoteRoutingPipelineStage` drops the `onComplete` callback; returns a `NoteRoutingResult` enum instead
- `TranscriptionPipelineStage` drops the `store` dependency entirely — failure paths no longer call `markProcessed`; the caller handles failure marking
- `MemoConsumer` gains an optional `onRecordInserted: ((MemoRecord) -> Void)?` callback — after a successful `store.insert`, it calls this callback so the controller can yield to the queue stream. This keeps `MemoConsumer` ignorant of `AsyncStream` specifics
- A `CompositeWatcherLogger` fans out to multiple `WatcherLogger` conformers (testable pattern for dual logging)
- `FileWatcherLogger` accepts an injectable `rotationThreshold` (defaults to 10MB) for testability. Uses `NSLock` + `@unchecked Sendable` for thread safety (simpler than `DispatchQueue` for synchronous methods)
- `PipelineController` owns the queue loop, startup drain, failure marking, and `lastProcessedDate` update
- Cancellation is distinct from failure: when the controller's task is cancelled (via `stop()`), in-flight items are NOT marked as failed — they remain unprocessed and will be picked up on next startup

---

## Task 0: Contracts and Shared Types

**Goal**: Define the new interfaces that all subsequent tasks depend on. No behavioral changes — only type definitions, protocol updates, and stubs that keep the package compiling.

**Relevant Files**:
- `Libraries/Sources/Core/MemoRecord.swift` — add failure fields
- `Libraries/Sources/Core/MemoStore.swift` — add `markFailed` and `allUnprocessed` to protocol
- `Libraries/Sources/Core/JSONMemoStore.swift` — add stub implementations (`fatalError`) so the package compiles
- `Libraries/Tests/CoreTests/Mocks/MockMemoStore.swift` — add `markFailed` tracking, update `oldestUnprocessed()` filter

**Context to Read First**:
- [MemoRecord.swift](../../Libraries/Sources/Core/MemoRecord.swift) — current struct definition, `Codable` conformance
- [MemoStore.swift](../../Libraries/Sources/Core/MemoStore.swift) — current protocol surface
- [JSONMemoStore.swift](../../Libraries/Sources/Core/JSONMemoStore.swift) — needs stubs to compile after protocol changes
- [MockMemoStore.swift](../../Libraries/Tests/CoreTests/Mocks/MockMemoStore.swift) — current mock, needs `markFailed` and updated `oldestUnprocessed()` to exclude failed records

**Changes**:

1. Add to `MemoRecord`:
   ```swift
   public var dateFailed: Date?
   public var failureReason: String?
   ```
   Update `init` to accept these as optional parameters with `nil` defaults. The struct is already `Codable` — optional fields with nil defaults are backward-compatible (old JSON without these keys decodes to nil).

2. Add to `MemoStore` protocol:
   ```swift
   func markFailed(fileURL: URL, reason: String, date: Date) async throws
   func allUnprocessed() async -> [MemoRecord]
   ```

3. Add stub implementations to `JSONMemoStore` so the package compiles:
   ```swift
   public func markFailed(fileURL: URL, reason: String, date: Date) throws {
       fatalError("Not yet implemented — see Task 1")
   }
   public func allUnprocessed() -> [MemoRecord] {
       fatalError("Not yet implemented — see Task 1")
   }
   ```

4. Update `MockMemoStore`:
   - Add `markFailedCalls: [(fileURL: URL, reason: String, date: Date)]` tracking array
   - Add `failedURLs: Set<URL>` — a set that `markFailed()` appends to AND that `oldestUnprocessed()` uses for filtering. This is distinct from `markFailedCalls` (which is observation-only). Both are updated by `markFailed()`
   - Implement `markFailed` to append to `markFailedCalls` and insert into `failedURLs`
   - Add `allUnprocessedResult: [MemoRecord]` property (settable, independent of `oldestUnprocessedResult`) and implement `allUnprocessed()` to return it
   - Update `oldestUnprocessed()` to exclude records whose fileURL is in `failedURLs`

**Verification**: `cd Libraries && timeout 120 swift test </dev/null 2>&1` — all existing tests must still pass. The `JSONMemoStore` stubs compile but are never called by existing tests.

**Do NOT**:
- Change any behavioral logic — this task is pure type/protocol definition + stubs
- Remove `oldestUnprocessed()` from the protocol — it's still used and its filter just needs updating
- Add a `markFailed` error property to `MockMemoStore` yet — keep it simple; tests that need error simulation can add it later
- Implement real logic in `JSONMemoStore` — that's Task 1. Only add `fatalError` stubs

**Blocked By**: Nothing

---

## Task 1: JSONMemoStore — markFailed, allUnprocessed, updated filter

**Goal**: Implement the new `MemoStore` protocol methods in `JSONMemoStore` and update the `oldestUnprocessed()` filter to exclude failed records. Verify backward compatibility with old store files.

**Relevant Files**:
- `Libraries/Sources/Core/JSONMemoStore.swift` — replace stubs with real implementations, update filter
- `Libraries/Tests/CoreTests/JSONMemoStoreTests.swift` — add tests

**Context to Read First**:
- [JSONMemoStore.swift](../../Libraries/Sources/Core/JSONMemoStore.swift) — current actor implementation, `write()` pattern, rollback pattern in `markProcessed`
- [JSONMemoStoreTests.swift](../../Libraries/Tests/CoreTests/JSONMemoStoreTests.swift) — existing test patterns (temp file, reload-from-disk verification)

**Acceptance Criteria (GIVEN/WHEN/THEN)**:
- AC-3.6: GIVEN a store with one record where `dateFailed` is set and `dateProcessed` is nil, WHEN `oldestUnprocessed()` is called, THEN it returns nil
- AC-3.5: GIVEN a record marked failed via `markFailed`, WHEN a new `JSONMemoStore` is loaded from the same file, THEN `dateFailed` and `failureReason` are preserved
- AC-3.9: GIVEN a JSON file containing records without `dateFailed`/`failureReason` fields, WHEN `JSONMemoStore` is initialized from it, THEN all records decode successfully with nil failure fields and retain their `dateProcessed` values
- `allUnprocessed()` returns records where both `dateProcessed` and `dateFailed` are nil, ordered by `dateCreated` ascending
- `markFailed` throws `recordNotFound` for unknown URLs
- `markFailed` rolls back on write failure (same pattern as `markProcessed`)

**TDD Steps**:

1. **RED**: Write test `markFailedSetsFieldsAndPersists` — insert a record, call `markFailed(fileURL:reason:date:)`, reload from disk, assert `dateFailed` and `failureReason` are set on the reloaded record
2. **GREEN**: Replace the `fatalError` stub in `JSONMemoStore.markFailed` with a real implementation following the `markProcessed` pattern (find record by normalized URL, set `dateFailed` and `failureReason`, call `write()`, rollback both fields on error)
3. **RED**: Write test `oldestUnprocessedExcludesFailedRecords` — insert a record, call `markFailed`, assert `oldestUnprocessed()` returns nil
4. **GREEN**: Update `oldestUnprocessed()` filter: `records.filter { $0.dateProcessed == nil && $0.dateFailed == nil }`
5. **RED**: Write test `allUnprocessedReturnsOnlyUnprocessedRecordsInOrder` — insert 3 records with distinct `dateCreated` offsets (one processed via `markProcessed`, one failed via `markFailed`, one unprocessed), assert `allUnprocessed()` returns only the unprocessed one
6. **GREEN**: Replace the `fatalError` stub in `allUnprocessed()` — filter for `dateProcessed == nil && dateFailed == nil`, sort by `dateCreated` ascending
7. **RED**: Write test `allUnprocessedReturnsMultipleInDateOrder` — insert 3 unprocessed records with offsets 300, 100, 200, assert `allUnprocessed()` returns them ordered [100, 200, 300]
8. **GREEN**: Already passes from step 6's sort
9. **RED**: Write test `markFailedThrowsForUnknownURL` — assert `MemoStoreError.recordNotFound`
10. **GREEN**: Already passes from the implementation in step 2
11. **RED**: Write test `markFailedRollsBackOnWriteFailure` — use the non-writable directory pattern from existing `markProcessedRollsBackOnWriteFailure` test
12. **GREEN**: Already passes from the rollback pattern in step 2
13. **RED**: Write test `backwardCompatibilityDecodesOldRecordsWithoutFailureFields` — write a hardcoded JSON string with records that have `fileURL`, `dateCreated`, `dateProcessed` but NO `dateFailed`/`failureReason` keys. Load store, assert records decode with `dateFailed == nil` and `failureReason == nil`, and `dateProcessed` values are preserved
14. **GREEN**: Already passes since the fields are optional with nil defaults — do NOT add a custom `init(from:)` unless the compiler requires it

**Verification**: `cd Libraries && timeout 120 swift test </dev/null 2>&1`

**Do NOT**:
- Change `markProcessed` behavior — it stays as-is
- Remove `oldestUnprocessed()` — just update its filter
- Add methods not on the protocol
- Add a custom `Codable` `init(from:)` — the synthesized one handles optional fields correctly

**Blocked By**: Task 0

---

## Task 2: Pipeline Stages — Return Failure Info Instead of Marking Processed

**Goal**: Change `TranscriptionPipelineStage` and `NoteRoutingPipelineStage` so they report failures to the caller instead of calling `store.markProcessed()` on error paths. Remove the `onComplete` callback from `NoteRoutingPipelineStage`. Remove the dead `store` dependency from `TranscriptionPipelineStage`. Also delete `PipelineControllerTests.swift` (it references the removed `onComplete` API and will be fully rewritten in Task 3).

**Relevant Files**:
- `Libraries/Sources/Core/TranscriptionPipelineStage.swift` — remove `store` dependency, remove `store.markProcessed` calls on failure paths
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` — remove `onComplete` callback, remove `store.markProcessed` call on failure path; return a result enum
- `Libraries/Tests/CoreTests/TranscriptionPipelineStageTests.swift` — update failure tests, remove `store` from init calls
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` — update all tests (remove `onComplete` wiring), update failure tests
- `Libraries/Tests/CoreTests/PipelineControllerTests.swift` — delete (uses removed `onComplete` API; fully rewritten in Task 3)

**Context to Read First**:
- [TranscriptionPipelineStage.swift](../../Libraries/Sources/Core/TranscriptionPipelineStage.swift) — `store` property (line 10), failure paths at lines 33-34 and 50-53 call `store.markProcessed`
- [NoteRoutingPipelineStage.swift](../../Libraries/Sources/Core/NoteRoutingPipelineStage.swift) — `onComplete` in init (line 14, 27), called on every path (lines 48, 59); `store.markProcessed` on failure path (line 55, falls through from catch on line 50-52)
- [TranscriptionPipelineStageTests.swift](../../Libraries/Tests/CoreTests/TranscriptionPipelineStageTests.swift) — tests 6-7 assert `markProcessedCalls.count == 1` on failure; all tests pass `store` to init
- [NoteRoutingPipelineStageTests.swift](../../Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift) — test 7 asserts `markProcessedCalls.count == 1` on error path; `makeStage` helper passes `onComplete`; test 2 asserts `completeCounter == 1`
- [PipelineControllerTests.swift](../../Libraries/Tests/CoreTests/PipelineControllerTests.swift) — constructs `NoteRoutingPipelineStage` with `onComplete:` parameter; will not compile after removal

**Acceptance Criteria (GIVEN/WHEN/THEN)**:
- AC-3.8: GIVEN `TranscriptionPipelineStage` fails to transcribe, WHEN the failure is handled, THEN `process()` returns nil AND `store.markProcessed` is NOT called AND `store.markFailed` is NOT called (the caller handles failure marking)
- AC-3.7: GIVEN `NoteRoutingPipelineStage` processes a memo where note creation fails, WHEN the failure is handled, THEN `route()` returns `.failure(reason:)` AND `store.markProcessed` is NOT called
- `NoteRoutingPipelineStage.init` no longer accepts an `onComplete` parameter
- On success, `NoteRoutingPipelineStage.route()` still calls `store.markProcessed` and returns `.success`
- On cancellation, `NoteRoutingPipelineStage.route()` returns `.cancelled` without calling the store
- `TranscriptionPipelineStage.init` no longer accepts a `store` parameter
- All existing behavioral tests for success paths continue to pass (with updated init signatures)

**Design**:

`TranscriptionPipelineStage`: Remove the `store` property and `store` init parameter entirely. After Task 2, this stage has no store dependency — it only transcribes and returns results. Update all 8 test call sites and the production call site in PipelineController (which is being deleted in Task 3 anyway, so only tests matter here).

For `NoteRoutingPipelineStage`, introduce a result type:
```swift
public enum NoteRoutingResult: Sendable, Equatable {
    case success
    case failure(reason: String)
    case cancelled
}
```
Change `route()` to return `NoteRoutingResult` instead of `Void`. On success, it still calls `store.markProcessed`, then returns `.success`. On failure from `routeCore`, return `.failure(reason: error.localizedDescription)` without calling `store.markProcessed`. On cancellation, return `.cancelled`.

**TDD Steps**:

1. **RED**: Update `TranscriptionPipelineStageTests.transcriptionFailureLogsAndCallsMarkProcessed` — rename to `transcriptionFailureLogsAndDoesNotCallStore`, remove `store` from `TranscriptionPipelineStage` init call, assert `result == nil` and logger has errors. (Compile error on init drives the change.)
2. **GREEN**: Remove `store` property and init parameter from `TranscriptionPipelineStage`. Remove the two `store.markProcessed` calls from failure paths (lines 34 and 53). Update all other test init calls to remove `store:` argument.
3. **RED**: Update `TranscriptionPipelineStageTests.missingFileCausesFailureAndCallsMarkProcessed` — rename, remove store, assert `result == nil`
4. **GREEN**: Already passes from step 2
5. **RED**: Define `NoteRoutingResult` enum. Update `NoteRoutingPipelineStageTests.markProcessedAndOnCompleteRunExactlyOnceOnErrorPath` — remove `onComplete` from init, assert `markProcessedCalls.count == 0` on error path, capture return value: `let routeResult = await stage.route(result)`, assert `routeResult` is `.failure` with a non-empty reason
6. **GREEN**: Remove `onComplete` from `NoteRoutingPipelineStage.init` and all internal call sites. Change `route()` to return `NoteRoutingResult`. On success path (after `routeCore` succeeds), keep `store.markProcessed`, return `.success`. On non-cancellation error from `routeCore`, return `.failure(reason: error.localizedDescription)` WITHOUT calling `store.markProcessed`. On cancellation, return `.cancelled`
7. **RED**: Update `makeStage` helper in tests to remove `completeCounter` parameter and `onComplete`. Update test 6 (success path): capture return `let routeResult = await stage.route(result)`, assert `routeResult == .success` and `markProcessedCalls.count == 1`
8. **GREEN**: Already passes from step 6
9. **RED**: Add test `cancellationReturnsNoCancelledResult` — trigger `CancellationError` from `routeCore` (by cancelling the task), assert return is `.cancelled` and `markProcessedCalls.count == 0`
10. **GREEN**: Already passes from step 6's cancellation path
11. Update all remaining `NoteRoutingPipelineStageTests` to remove `completeCounter`/`onComplete` assertions and use updated `makeStage` helper
12. Delete `PipelineControllerTests.swift` — it references the old `onComplete` API and `PipelineScheduler` behavior. Task 3 creates the replacement tests.

**Verification**: `cd Libraries && timeout 120 swift test </dev/null 2>&1`

**Do NOT**:
- Have the stages call `store.markFailed` — that responsibility belongs to the queue (Task 3)
- Change any success-path behavior in `NoteRoutingPipelineStage` — it still calls `store.markProcessed` on success, then returns `.success`
- Change summarization, title generation, or folder resolution logic
- Keep the `store` dependency in `TranscriptionPipelineStage` — it becomes dead code after removing the failure-path calls

**Blocked By**: Task 0

---

## Task 3: PipelineController — Immediate Queue with Dead Queue

**Goal**: Rewrite `PipelineController` to use an immediate queue instead of `PipelineScheduler`. The controller receives memo events, enqueues them, processes sequentially, marks failures, and drains unprocessed records on startup.

**Relevant Files**:
- `Libraries/Sources/Core/PipelineController.swift` — full rewrite
- `Libraries/Sources/Core/MemoConsumer.swift` — add `onRecordInserted` callback
- `Libraries/Sources/Core/PipelineScheduler.swift` — delete
- `Libraries/Tests/CoreTests/PipelineControllerTests.swift` — create (was deleted in Task 2)
- `Libraries/Tests/CoreTests/PipelineSchedulerTests.swift` — delete
- `Libraries/Tests/CoreTests/MemoConsumerTests.swift` — add test for new callback

**Context to Read First**:
- [PipelineController.swift](../../Libraries/Sources/Core/PipelineController.swift) — current wiring: MemoConsumer + PipelineScheduler + handler closure
- [PipelineScheduler.swift](../../Libraries/Sources/Core/PipelineScheduler.swift) — being deleted; understand the lock/timeout behavior so nothing critical is lost (timeout is a known regression — documented in plan as accepted tradeoff)
- [MemoConsumer.swift](../../Libraries/Sources/Core/MemoConsumer.swift) — current `consume(_ stream:)` method; needs `onRecordInserted` callback added to init
- [MemoConsumerTests.swift](../../Libraries/Tests/CoreTests/MemoConsumerTests.swift) — existing tests for consumer; new callback test needed
- [NoteRoutingPipelineStage.swift](../../Libraries/Sources/Core/NoteRoutingPipelineStage.swift) — `route()` now returns `NoteRoutingResult` (from Task 2)
- [TranscriptionPipelineStage.swift](../../Libraries/Sources/Core/TranscriptionPipelineStage.swift) — `process()` no longer takes `store` (from Task 2)

**Acceptance Criteria (GIVEN/WHEN/THEN)**:

- AC-1.1: GIVEN the queue is idle, WHEN a new memo event arrives, THEN processing begins without any timer delay
- AC-1.2: GIVEN multiple memo events arrive, WHEN they are enqueued, THEN they are processed sequentially in insertion order
- AC-1.3: GIVEN N unprocessed records, WHEN the queue drains, THEN no unprocessed records remain
- AC-2.1: GIVEN unprocessed records exist in the store at startup, WHEN `start()` is called, THEN all unprocessed records are processed
- AC-2.2: GIVEN the store has two unprocessed records and the watcher emits one new event at start, WHEN `start()` is called, THEN the two pre-existing records are fully processed before the new event — verified by checking processing order in `ActorBox<[URL]>`
- AC-2.3/2.4: GIVEN failed or already-processed records exist at startup, WHEN `start()` is called, THEN they are not re-enqueued (verified via `allUnprocessedResult` returning only the eligible records)
- AC-3.1 (covers plan AC-3.1 + AC-3.8 at controller level): GIVEN a transcription failure, WHEN the queue handles it, THEN `store.markFailed` is called exactly once with a non-empty reason, AND `store.markProcessed` is NOT called, AND the queue moves to the next item
- AC-3.2/3.3 (covers plan AC-3.2 + AC-3.3 + AC-3.7 at controller level): GIVEN a routing failure, WHEN the queue handles it, THEN `store.markFailed` is called exactly once with a non-empty reason, AND `store.markProcessed` is NOT called for the failed record, AND the queue moves to the next item
- Cancellation: GIVEN `stop()` is called while an item is being processed, WHEN the controller tears down, THEN `markFailed` is NOT called for the in-flight item (it remains unprocessed for next startup)
- `stop()` cancels the processing loop and consumer task
- `onItemProcessed` callback fires after each successful processing (after `markProcessed` succeeds), not on failure or cancellation

**Design**:

**MemoConsumer change**: Add an optional `onRecordInserted: (@Sendable (MemoRecord) -> Void)?` parameter to `MemoConsumer.init`. After a successful `store.insert(record)`, call `onRecordInserted?(record)`. This keeps `MemoConsumer` ignorant of `AsyncStream` specifics. The `PipelineController` passes a closure that yields to the queue continuation. Existing `MemoConsumerTests` continue to work (the parameter defaults to nil).

**PipelineController**:
```swift
@MainActor
public final class PipelineController {
    // Init takes: store, transcriptionService, watcherStream, logger,
    //             makeRoutingStage factory (no onComplete), onItemProcessed callback

    public func start() async {
        // 1. Create AsyncStream<MemoRecord> queue with unbounded buffering
        // 2. Drain: call store.allUnprocessed(), yield each record to continuation
        //    (synchronous on @MainActor — no suspension points between drain and consumer start)
        // 3. Create MemoConsumer with onRecordInserted that yields to continuation
        // 4. Launch consumer Task
        // 5. Launch processing Task: for await record in queue { processOne(record) }
    }

    public func stop() { ... }
}
```

**Startup drain ordering guarantee**: The drain loop yields all records synchronously to the continuation before the consumer `Task` is spawned. Because steps 1-2 run on `@MainActor` before any suspension point, no consumer events can be interspersed.

**Processing loop** (`for await record in queue`):
1. Call `transcriptionStage.process(record)`
2. If nil AND `Task.isCancelled` → break (don't mark failed — cancellation is not failure)
3. If nil AND NOT cancelled → `store.markFailed(fileURL:reason:"Transcription failed":date:)`; continue
4. If routing stage exists → call `routingStage.route(result)`
   - `.success` → call `onItemProcessed()`; continue
   - `.failure(reason:)` → `store.markFailed(fileURL:reason:date:)`; continue
   - `.cancelled` → break (don't mark failed)
5. If no routing stage → `store.markProcessed(fileURL:date:)`; call `onItemProcessed()`; continue

**TDD Steps**:

1. **RED**: Write test `memoConsumerCallsOnRecordInserted` — create `MemoConsumer` with a captured `onRecordInserted` callback, feed one event, assert the callback receives the `MemoRecord` with the matching URL. (In `MemoConsumerTests.swift`)
2. **GREEN**: Add `onRecordInserted: (@Sendable (MemoRecord) -> Void)? = nil` to `MemoConsumer.init`. After `try await store.insert(record)` succeeds, call `onRecordInserted?(record)`.
3. **RED**: Write test `immediateProcessingOnNewEvent` — create `PipelineController` with a continuation-controlled watcher stream that emits one event. Use `ActorBox<Int>` to track transcription calls. After yielding one event and finishing the stream, assert `transcriptionService.transcribeCalls.count == 1`. Use `withCheckedContinuation` to wait for the processing to complete rather than `Task.sleep`.
4. **GREEN**: Implement the basic queue loop in `PipelineController` — create `AsyncStream<MemoRecord>`, create consumer with `onRecordInserted` that yields to continuation, start processing loop.
5. **RED**: Write test `sequentialProcessingOfMultipleEvents` — emit 3 events with distinct URLs, use `ActorBox<[URL]>` to track processing order, assert URLs appear in emission order.
6. **GREEN**: Already passes from step 4 (sequential by nature of `for await`).
7. **RED**: Write test `startupDrainProcessesExistingRecords` — set `MockMemoStore.allUnprocessedResult` to 2 records, start controller with empty watcher stream, assert both are transcribed.
8. **GREEN**: Add startup drain to `start()` — call `store.allUnprocessed()`, yield each to the continuation before spawning the consumer task.
9. **RED**: Write test `startupDrainBeforeNewEvents` — set `allUnprocessedResult` to 2 records, emit 1 new event via watcher stream, use `ActorBox<[URL]>` to track order, assert the 2 drain records appear before the new event's record.
10. **GREEN**: Ensure drain yields are synchronous before consumer `Task` is spawned (see ordering guarantee above).
11. **RED**: Write test `transcriptionFailureCallsMarkFailed` — configure `MockTranscriptionService.error` to throw, assert `store.markFailedCalls.count == 1` with a non-empty reason string. Also assert `store.markProcessedCalls` is empty.
12. **GREEN**: Add failure handling: after `stage.process()` returns nil, check `Task.isCancelled` — if not cancelled, call `store.markFailed`.
13. **RED**: Write test `routingFailureCallsMarkFailed` — configure `MockNotesService.createNoteError` to trigger a `.failure(reason:)` return from the routing stage. Assert `store.markFailedCalls.count == 1` with a non-empty reason. Assert `store.markProcessedCalls` has no entry for the failed record's URL.
14. **GREEN**: Add failure handling after `routingStage.route()` returns `.failure`.
15. **RED**: Write test `successCallsOnItemProcessed` — use `ActorBox<Int>` to count `onItemProcessed` calls. Assert it fires exactly once on success.
16. **GREEN**: Add `onItemProcessed()` call after successful processing (after `markProcessed` succeeds or after routing returns `.success`).
17. **RED**: Write test `stopCancelsProcessingLoop` — start controller, emit events, call `stop()`, wait briefly, assert no more processing occurs (snapshot `transcribeCalls.count` after stop, wait, assert unchanged).
18. **GREEN**: Implement `stop()` — cancel the processing task and consumer task.
19. **RED**: Write test `cancellationDoesNotMarkFailed` — start controller, emit an event where transcription takes a long time (use a mock that awaits a signal), call `stop()` before it completes, assert `store.markFailedCalls.isEmpty` and the record remains unprocessed.
20. **GREEN**: Already passes from step 12's `Task.isCancelled` check.
21. **RED**: Write test `startupDrainSkipsFailedAndProcessedRecords` — set `allUnprocessedResult = []` (simulating a store where all records are either processed or failed). Start controller with empty watcher stream. Assert `transcriptionService.transcribeCalls.count == 0`.
22. **GREEN**: Already passes since `allUnprocessed()` returns empty array.
23. **RED**: Write test `startupDrainWithMixedRecords` — set `allUnprocessedResult` to one record (the unprocessed one; the store has already filtered out failed/processed). Assert `transcribeCalls.count == 1` and the transcribed URL matches the unprocessed record.
24. **GREEN**: Already passes from step 8.
25. Delete `PipelineScheduler.swift` and `PipelineSchedulerTests.swift`.

**Verification**: `cd Libraries && timeout 120 swift test </dev/null 2>&1`

**Do NOT**:
- Keep any reference to `PipelineScheduler` — it's fully deleted
- Use `Task.sleep` for synchronization in tests — use `ActorBox` + continuation signaling (e.g., `withCheckedContinuation` to create a resume-on-completion signal captured in an `ActorBox`, then `await` it)
- Use a `Clock` parameter — the queue is event-driven, no polling
- Add retry logic — failed items go to dead queue permanently
- Have the controller call `store.markProcessed` on failure — only `store.markFailed`
- Call `markFailed` when `Task.isCancelled` is true — cancellation is not failure
- Modify `MemoConsumer.consume()` signature — only add the `onRecordInserted` callback to init

**Blocked By**: Task 0, Task 1, Task 2

---

## Task 4: File Logger and Composite Logger

**Goal**: Create a `FileWatcherLogger` that writes to disk with rotation, and a `CompositeWatcherLogger` that fans out to multiple loggers. Both conform to `WatcherLogger`.

**Relevant Files**:
- `Libraries/Sources/Core/FileWatcherLogger.swift` — new file
- `Libraries/Sources/Core/CompositeWatcherLogger.swift` — new file
- `Libraries/Tests/CoreTests/FileWatcherLoggerTests.swift` — new file
- `Libraries/Tests/CoreTests/CompositeWatcherLoggerTests.swift` — new file

**Context to Read First**:
- [WatcherLogger.swift](../../Libraries/Sources/Core/WatcherLogger.swift) — protocol definition (info, warning, error)
- [OSLogWatcherLogger.swift](../../Utterd/Core/OSLogWatcherLogger.swift) — existing conformer pattern
- [MockWatcherLogger.swift](../../Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift) — mock pattern

**Acceptance Criteria (GIVEN/WHEN/THEN)**:

- AC-4.1: GIVEN a `FileWatcherLogger` at a temp path, WHEN `info("a")`, `warning("b")`, `error("c")` are called, THEN the file contains all three messages
- AC-4.3: GIVEN a `FileWatcherLogger` with `rotationThreshold: 1024` bytes, WHEN more than 1024 bytes are written, THEN the file is truncated and the newly-written line appears in the file after rotation (confirming writes-after-truncation succeed). Default threshold is 10MB.
- AC-4.4: GIVEN a `CompositeWatcherLogger` with two `MockWatcherLogger` children, WHEN `info("msg")` is called, THEN both children receive `"msg"`
- The file logger includes a timestamp and level prefix in each line (e.g., `[2026-04-04 14:30:00] [INFO] message`)
- If the log file cannot be created, the logger silently no-ops (does not crash). Subsequent calls also silently no-op.
- `FileWatcherLogger` conforms to `Sendable` via `NSLock` + `@unchecked Sendable`

**Design**:

`FileWatcherLogger`:
- Init: `(fileURL: URL, rotationThreshold: Int = 10 * 1024 * 1024)`
- Uses `FileHandle` for appending. On each write, checks file size; if current size + new line > threshold, truncates the file, then writes the new line.
- Thread safety: `NSLock` wrapping all `FileHandle` operations. Mark as `@unchecked Sendable`.
- If the file cannot be opened/created at init time, all subsequent log calls silently no-op.

`CompositeWatcherLogger`:
- Init: `([any WatcherLogger])`
- Forwards each call to all children. Simple and synchronous.
- Conforms to `Sendable` (children are `any WatcherLogger` which is `Sendable`).

**TDD Steps**:

1. **RED**: Write test `infoWarningErrorWrittenToFile` — create `FileWatcherLogger` at a temp path, call all three methods, read file contents, assert all messages present.
2. **GREEN**: Implement `FileWatcherLogger` — create/open file, format lines as `[timestamp] [LEVEL] message\n`, append via `FileHandle`.
3. **RED**: Write test `rotationTruncatesAtThreshold` — create logger with `rotationThreshold: 1024`, write enough lines to exceed 1024 bytes, read file, assert file size is under 1024 + one line, and assert the last-written line is present in the file.
4. **GREEN**: Add rotation check before each write — if current file size + new line length > threshold, truncate the file (seek to 0, truncate), then write the new line.
5. **RED**: Write test `gracefulNoOpWhenFileNotWritable` — create logger at `/nonexistent-dir/test.log`, call `info("msg")` multiple times, assert no crash and file does not exist.
6. **GREEN**: Wrap file operations in do/catch, set a `fileHandle: FileHandle?` that stays nil on failure, check for nil before each write.
7. **RED**: Write test `compositeForwardsToAllChildren` — create `CompositeWatcherLogger` with 2 `MockWatcherLogger`s, call `info`, `warning`, `error`, assert both received all 3 messages.
8. **GREEN**: Implement `CompositeWatcherLogger` — store children array, iterate and forward each call.
9. **RED**: Write test `logLineContainsTimestampAndLevel` — call `info("msg")`, read file, assert line matches format `[...] [INFO] msg` (regex or prefix/suffix check).
10. **GREEN**: Already passes from the formatting in step 2.

**Verification**: `cd Libraries && timeout 120 swift test </dev/null 2>&1`

**Do NOT**:
- Use `os.Logger` or OSLog in `FileWatcherLogger` — it writes directly to a file
- Add log levels beyond what `WatcherLogger` defines (info, warning, error)
- Buffer writes in memory — write-through on each call for durability
- Archive old log content on rotation — truncate and start fresh (per plan decision)
- Use `DispatchQueue` for thread safety — `NSLock` is simpler for synchronous methods

**Blocked By**: Nothing (independent of Tasks 0-3)

---

## Task 5: AppDelegate Wiring

**Goal**: Wire the new `PipelineController` (with queue), `CompositeWatcherLogger`, and `FileWatcherLogger` into the app's startup flow. Replace the `onComplete`-based `lastProcessedDate` update with the queue's `onItemProcessed` callback.

**Relevant Files**:
- `Utterd/App/AppDelegate.swift` — update `startPipeline()` and `makePipelineController()`
- `Utterd/Core/OSLogWatcherLogger.swift` — no changes (used as child of composite)

**Context to Read First**:
- [AppDelegate.swift](../../Utterd/App/AppDelegate.swift) — current `startPipeline()` (lines 72-110), `makePipelineController()` (lines 112-149), `storeFileURL()` (lines 160-173)
- [PipelineController.swift](../../Libraries/Sources/Core/PipelineController.swift) — new API from Task 3

**Acceptance Criteria (GIVEN/WHEN/THEN)**:
- GIVEN the app builds with the new wiring, WHEN `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build` runs, THEN it exits 0 with no errors
- GIVEN a `PipelineController` init, WHEN it is constructed without a `clock` parameter and without an `onComplete`-bearing routing stage factory, THEN it compiles
- The log file is created at `~/Library/Application Support/Utterd/utterd.log`
- `lastProcessedDate` updates after each successful processing via `onItemProcessed`

**Changes**:

1. In `startPipeline()`, create the log file URL alongside the store URL (reuse the `dir` variable from `storeFileURL`):
   ```swift
   let logURL = dir.appendingPathComponent("utterd.log")
   ```

2. Create the composite logger:
   ```swift
   let fileLogger = FileWatcherLogger(fileURL: logURL)
   let logger = CompositeWatcherLogger([OSLogWatcherLogger(), fileLogger])
   ```

3. In `makePipelineController()`:
   - Remove the `clock` parameter (no longer in `PipelineController.init`)
   - Change the routing stage factory signature from `(@escaping @Sendable () async -> Void) -> NoteRoutingPipelineStage` to `() -> NoteRoutingPipelineStage` (no `onComplete`)
   - Remove the `wrappedOnComplete` closure that updated `lastProcessedDate`
   - Pass `onItemProcessed` to `PipelineController`:
     ```swift
     onItemProcessed: { [weak self] in
         await MainActor.run { self?.appState?.lastProcessedDate = Date() }
     }
     ```
   - The `NoteRoutingPipelineStage` init call drops `onComplete:` parameter

4. Update `makePipelineController` return type and parameters — remove `clock: any Clock<Duration>` parameter.

5. In `startPipeline()`, remove the `ImmediateClock` or `ContinuousClock` reference if present in the controller creation.

**Verification**: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build`

**Do NOT**:
- Change `OSLogWatcherLogger` — it's used as-is inside the composite
- Remove the `storeFileURL` helper — it's still used
- Change the `#available(macOS 26, *)` guard — the pipeline is still gated
- Touch the permission gate or Settings UI code
- Add tests for AppDelegate wiring — build verification is sufficient; behavioral coverage is in Tasks 1-4

**Blocked By**: Task 3, Task 4

---

## Summary

| Task | Description | Files Modified | Files Created | Files Deleted | Blocked By |
|------|-------------|---------------|---------------|---------------|------------|
| 0 | Contracts: MemoRecord fields, MemoStore protocol, MockMemoStore, JSONMemoStore stubs | 4 | 0 | 0 | — |
| 1 | JSONMemoStore: markFailed, allUnprocessed, updated filter | 2 | 0 | 0 | 0 |
| 2 | Pipeline stages: return failure info, remove onComplete, remove store from transcription stage | 4 | 0 | 1 | 0 |
| 3 | PipelineController: immediate queue, dead queue, startup drain, MemoConsumer callback | 3 | 1 | 2 | 0, 1, 2 |
| 4 | FileWatcherLogger + CompositeWatcherLogger | 0 | 4 | 0 | — |
| 5 | AppDelegate wiring | 1 | 0 | 0 | 3, 4 |

**Parallelism**: Tasks 1, 2, and 4 can run in parallel (no file overlap, independent concerns). Task 3 depends on 0, 1, and 2. Task 5 depends on 3 and 4.

```
Task 0 ──┬──▶ Task 1 ──┐
         ├──▶ Task 2 ──┤
         │              ├──▶ Task 3 ──┐
Task 4 ──┼──────────────┘            ├──▶ Task 5
         └───────────────────────────┘
```

---

## Open Questions

None — all decisions resolved during planning.
