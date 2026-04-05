# Plan: Immediate Queue-Based Pipeline

**Status**: Approved
**Created**: 2026-04-04
**Branch**: `immediate-execution`

---

## Why This Exists

Voice memos sit unprocessed for up to 30 seconds after detection because the pipeline uses a fixed-interval polling scheduler. For a tool meant to feel frictionless, a half-minute delay between recording and note creation undermines the core promise. Additionally, when processing fails, the current system either silently marks the record as processed (hiding the failure) or retries indefinitely — there is no way to see what failed or why. Finally, pipeline log messages only go to macOS unified logging (Console.app), which most users will never open. There is no persistent, inspectable log file on disk.

---

## What We Are Building

Three changes to the voice memo processing pipeline:

1. **Immediate queue-based processing.** When the file system watcher detects a new voice memo, it is written to the store and immediately enqueued for processing. The queue processes items sequentially (one at a time) and drains until empty. On app startup, any unprocessed records left from a prior session are drained first before listening for new events. The 30-second polling scheduler is removed entirely.

2. **Dead queue for failed items.** When processing fails at any stage (transcription, LLM summarization/title generation, or note creation), the record is marked as failed with a timestamp and error reason. Failed items are never retried. This replaces the current behavior of silently marking failures as "processed."

3. **Persistent log file.** Pipeline log messages are written to a file on disk in addition to macOS unified logging. The file rotates at 10MB — old content is discarded (not archived).

---

## Scope

### In

- Detected memos begin processing immediately rather than waiting for a polling interval
- Sequential processing guarantee — one memo at a time, no concurrent processing
- On startup, unprocessed records from prior sessions are drained before new events are handled
- Failed items are permanently recorded with a failure reason and timestamp, distinct from successfully processed items
- Pipeline stages report failure back to the caller instead of silently marking records as processed
- The completion callback on the note routing stage is removed; the queue drives sequencing
- The "last processed" timestamp displayed in the menu bar continues to update after each successful processing (ownership moves from the completion callback to the queue's post-processing path)
- The polling-based scheduler and its tests are deleted
- A new file-based logger writes pipeline messages to disk with 10MB rotation
- The file logger is wired alongside (not replacing) the existing unified logging
- All affected tests are updated or rewritten

### Out

- Retry logic for failed items — failures are permanent
- UI for viewing failed items or log file contents (future work)
- Changes to file system event detection or memo qualification logic
- Remote logging or log aggregation
- Changes to transcription or note routing internal logic (only their failure reporting interface changes)
- The lock-release callback mechanism is eliminated along with the scheduler — no replacement lock is needed since the queue provides natural sequential processing

---

## User Stories

### US-1: Immediate processing
When a voice memo is detected, it begins processing within seconds rather than waiting for the next polling cycle. If multiple memos arrive while one is processing, they queue up and are processed in order.

**Acceptance Criteria:**
- AC-1.1: GIVEN the queue is idle, WHEN a new memo is detected, THEN processing begins without any timer delay — verified by the processing log emitting an entry for the memo without an intervening sleep cycle
- AC-1.2: GIVEN multiple memos are detected in separate file system events, WHEN they are enqueued, THEN they are processed sequentially in the order they were inserted into the store. For memos coalesced into a single file system event batch, processing order is undefined
- AC-1.3: GIVEN N unprocessed records in the queue, WHEN the queue processes all of them, THEN no unprocessed records remain in the store

### US-2: Startup recovery
When the app launches and there are unprocessed records from a prior session, those records are processed before the app begins listening for new file events.

**Acceptance Criteria:**
- AC-2.1: On startup, all unprocessed records in the store are enqueued for processing
- AC-2.2: GIVEN the store has two unprocessed records and the watcher emits one new event at app start, WHEN the pipeline starts, THEN the two pre-existing records are fully processed before the new event enters the processing queue
- AC-2.3: Records that were already processed or already failed are not re-enqueued
- AC-2.4: GIVEN a store containing one failed record and one unprocessed record, WHEN the startup drain runs, THEN only the unprocessed record is enqueued — the failed record is skipped

### US-3: Failed items are visible and permanent
When processing fails at any pipeline stage, the failure is recorded with a reason and timestamp. The item is never retried.

**Acceptance Criteria:**
- AC-3.1: GIVEN a memo in the queue, WHEN transcription fails, THEN the store records the item as failed with a non-empty reason string and a failure timestamp, AND the item is NOT marked as processed
- AC-3.2: GIVEN a memo in the queue, WHEN LLM summarization or title generation fails, THEN the store records the item as failed with a non-empty reason string and a failure timestamp, AND the item is NOT marked as processed
- AC-3.3: GIVEN a memo in the queue, WHEN note creation fails, THEN the store records the item as failed with a non-empty reason string and a failure timestamp, AND the item is NOT marked as processed
- AC-3.4: GIVEN a record marked as failed, WHEN the store is queried for unprocessed records, THEN the failed record is not returned
- AC-3.5: GIVEN a record marked as failed, WHEN the app is restarted and the store is reloaded from disk, THEN the failure reason and timestamp are preserved
- AC-3.6: GIVEN a store containing one record with a failure timestamp set and no processed timestamp, WHEN the store is queried for the oldest unprocessed record, THEN it returns nil — the failed record is excluded by the filter
- AC-3.7: GIVEN the note routing stage processes a memo where note creation fails, WHEN the failure is handled, THEN the store records the item as failed exactly once with a non-empty reason, AND the item is NOT marked as processed
- AC-3.8: GIVEN the transcription stage fails to transcribe a memo, WHEN the failure is handled, THEN the store records the item as failed exactly once with a non-empty reason, AND the item is NOT marked as processed
- AC-3.9: GIVEN a store file containing records written before the failure fields existed (no failure timestamp or reason in the JSON), WHEN the store is loaded, THEN all records decode successfully with nil failure fields, AND previously processed records retain their processed timestamps

### US-4: Pipeline activity is logged to a file
Pipeline log messages are written to a persistent file on disk so the user can inspect what happened without Console.app.

**Acceptance Criteria:**
- AC-4.1: GIVEN a file logger initialized at a path, WHEN info, warning, and error messages are logged, THEN all three messages appear in the file at that path
- AC-4.2: The log file lives at a predictable location in Application Support
- AC-4.3: GIVEN a file logger with a configurable rotation threshold, WHEN the threshold is exceeded, THEN the log file is truncated and subsequent writes begin from the start of the file. The default threshold is 10MB
- AC-4.4: GIVEN both a file logger and a unified logger are wired, WHEN a pipeline message is logged, THEN both destinations receive the message

---

## Edge Cases

1. **Burst of events during processing**: Multiple memos detected while one is being transcribed. They are written to the store and enqueued. When the current item completes, the queue picks up the next one immediately. No memo is lost or processed concurrently.
2. **App crash mid-processing**: The item has no processed timestamp and no failure timestamp. On next launch, it is picked up by the startup drain.
3. **Empty queue receives new event**: The queue is idle, a new event arrives — processing starts immediately without waiting for a timer or signal.
4. **All startup records are already processed or failed**: Startup drain finds nothing to do and proceeds to normal event listening without delay.
5. **Store write failure when marking failed**: If the store cannot persist the failure record (e.g., disk full), the item remains unprocessed and will be picked up on next startup — acceptable since it's an edge case of an edge case.
6. **Log file not writable**: If the log directory or file cannot be created, the app continues with unified logging only — file logging degrades gracefully.
7. **Rapid app restart**: Unprocessed items from the prior session are drained again. The store's duplicate-URL check prevents duplicate records. If a note was created but the store wasn't updated before the crash, a duplicate note is possible — this is an accepted tradeoff (the crash window is very small).
8. **New event arrives during startup drain**: The event is written to the store by the consumer. Once the drain completes, the queue picks up any records that arrived during the drain, ensuring nothing is missed.

---

## Success Criteria

1. A detected memo begins processing without any polling delay (excluding time spent processing items ahead of it in the queue)
2. Failed items are permanently recorded with a failure reason and timestamp — they are never silently marked as processed, and they are excluded from future processing
3. The app processes a backlog of unprocessed items on startup without user intervention
4. Pipeline log messages appear in a file on disk in Application Support
5. The log file does not grow beyond ~10MB
6. The detection → transcription → note creation path produces the same output as before; the "last processed" timestamp in the menu bar continues to update after each successful processing

---

## Technical Context

- **Language/concurrency**: Swift 6.2, strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`), `@MainActor` isolation on pipeline controller and watcher
- **Async patterns**: The queue can be built with Swift's `AsyncStream` — the watcher already emits events on one. A processing loop that `for await`s on a stream gives natural sequential, immediate processing
- **Persistence**: `JSONMemoStore` is an actor that persists `[MemoRecord]` as JSON. Adding fields to `MemoRecord` (which is `Codable`) requires handling decode of old records that lack the new fields (use optional fields with nil defaults). Backward compatibility must be tested: a JSON file without the new fields must load without decode errors
- **Logging**: `WatcherLogger` protocol with three methods (`info`, `warning`, `error`). New file logger must conform. No third-party logging dependencies. A composite/multicast logger that fans out to multiple `WatcherLogger` conformers is the natural testable pattern for AC-4.4
- **Test infrastructure**: Swift Testing framework, `MockMemoStore`, `MockWatcherLogger`, `ImmediateClock`, `ActorBox` helper for async assertions. New queue tests should use completion signaling via `ActorBox` rather than fixed `Task.sleep` durations wherever possible
- **App wiring**: `AppDelegate.startPipeline()` creates and starts the watcher and controller. Gated behind `#available(macOS 26, *)`. The `lastProcessedDate` update is currently wired via the `onComplete` callback in `AppDelegate.makePipelineController()` — this wiring must be replaced when `onComplete` is removed
- **Key implementation details for task.md**:
  - `PipelineScheduler.swift` — deleted entirely
  - `PipelineController.swift` — rewritten to use queue instead of scheduler
  - `NoteRoutingPipelineStage.swift` — `onComplete` callback removed from init and all call sites
  - `TranscriptionPipelineStage.swift` — failure paths stop calling `store.markProcessed`; return error info to caller
  - `MemoRecord.swift` — add optional `dateFailed: Date?` and `failureReason: String?` fields
  - `MemoStore.swift` — add `markFailed(fileURL:reason:date:)` method; `oldestUnprocessed()` may be kept but must exclude records where `dateFailed` is set
  - `JSONMemoStore.swift` — implement `markFailed`; update `oldestUnprocessed()` filter
  - `MockMemoStore.swift` — add `markFailed` tracking; update `oldestUnprocessed()` to respect failure state
  - New `FileWatcherLogger.swift` — conforms to `WatcherLogger`, writes to disk, injectable rotation threshold
  - New `CompositeWatcherLogger.swift` — fans out to multiple `WatcherLogger` conformers
  - `AppDelegate.swift` — wire composite logger, replace `onComplete`-based `lastProcessedDate` update
  - `OSLogWatcherLogger.swift` — no changes

---

## Dependencies

- **Spec**: `spec.md` — failure thresholds section states "each memo attempted once, no automatic retry" which aligns with the dead queue design
- **No external dependencies** — file logging and queue use only Foundation APIs

---

## Open Questions

None — all decisions resolved during planning.
