# Transcription Pipeline (Stage 1) Plan

**Date**: 2026-03-30
**Status**: Approved
**Author**: Dave + Claude
**Project Spec**: spec.md

---

## What We Are Building

A processing queue that receives detected voice memos, deduplicates them against a persistent store, and feeds them one-at-a-time through a speech-to-text transcription stage. When transcription completes, the system emits the transcript and file path for downstream processing (stage 2, future work). Until stage 2 exists, the pipeline will process exactly one memo and then pause — the processing lock remains held and the record stays unfinished until a future stage completes the cycle.

---

## Why This Exists

Voice memos are detected by the file watcher but nothing happens after that — they are observed and discarded. The user needs memos to flow through a reliable, crash-resilient queue that survives restarts, prevents duplicates, and produces transcripts that downstream stages can act on. Without this queue and transcription step, the entire routing pipeline (voice memo → Reminders/Calendar/Notes) cannot begin.

---

## Scope

### In
- Persistent datastore recording file path, date created, date processed, and a global processing lock
- Consumer that subscribes to file watcher events and inserts new (unseen) records into the datastore
- Continuously running scheduler (every 30 seconds) that checks for unprocessed items when the lock is free, picks the oldest, and sends it to the pipeline
- Pipeline stage that acquires the global lock, transcribes the audio via speech-to-text, and emits the transcript + file path
- Global processing lock that resets to `false` on app launch (crash recovery)

### Out (explicitly)
- LLM classification and routing (stage 2 — future work)
- Creating items in Reminders, Calendar, or Notes (stage 2 — future work)
- Setting `dateProcessed` or releasing the lock after successful transcription — that responsibility belongs to stage 2. Stage 1 only sets `dateProcessed` on permanent failure (to prevent infinite re-processing)
- Storing transcripts in the datastore — transcripts are emitted, not persisted
- Retry logic for failed transcriptions — spec says each memo is attempted once
- UI changes to the menu bar — no status display for the queue in this plan

---

## Technical Context

- **Platform**: macOS 15+ (Sequoia), Swift 6.2 with strict concurrency
- **Relevant systems**: `VoiceMemoWatcher` in `Libraries/Sources/Core/` emits `VoiceMemoEvent` (containing `fileURL` and `fileSize`) via `AsyncStream`. Multiple consumers are supported. The watcher already deduplicates within a single app session via in-memory set, but this does not survive restarts.
- **Speech-to-text**: macOS `SpeechAnalyzer` API (replaces the previously planned embedded-transcript extraction approach)
- **Constraints**: `SpeechAnalyzer` requires macOS 26+. No third-party dependencies for persistence (project policy). The app uses `@Observable` / `@MainActor` patterns throughout.

---

## User Stories

### US-01 — Memo enters the processing queue
As the app,
I want to record each newly detected voice memo in a persistent store,
So that memos are not lost across app restarts and are never processed twice.

**Acceptance Criteria**
- [ ] AC-01.1: GIVEN a voice memo event is received, WHEN no record with a matching file path exists in the datastore, THEN a new record is created with the full file path, current timestamp as date created, and null date processed
- [ ] AC-01.2: GIVEN a voice memo event is received, WHEN a record with a matching file path already exists in the datastore, THEN no new record is created and no error is raised
- [ ] AC-01.3: GIVEN the app is restarted, WHEN a previously recorded voice memo event arrives again, THEN it is recognized as a duplicate via file path match and ignored
- [ ] AC-01.4: GIVEN a voice memo event is received, WHEN the datastore cannot be written to (e.g., disk full, permissions error), THEN no record is created, the error is logged, and the memo is not sent to the pipeline for processing

---

### US-02 — Scheduler picks memos for processing
As the app,
I want a continuously running scheduler to feed unprocessed memos to the pipeline,
So that memos are transcribed without manual intervention.

**Acceptance Criteria**
- [ ] AC-02.1: GIVEN one or more records with dateProcessed equal to null exist in the datastore AND the global lock is false, WHEN the scheduler runs, THEN the record with the oldest date created is selected and sent to the pipeline
- [ ] AC-02.2: GIVEN the global lock is true, WHEN the scheduler runs, THEN no record is picked and the scheduler waits until the next cycle
- [ ] AC-02.3: GIVEN no unprocessed records exist, WHEN the scheduler runs, THEN no action is taken and the scheduler waits until the next cycle
- [ ] AC-02.4: GIVEN the app launches, WHEN 30 seconds elapse with unprocessed records (dateProcessed is null) and the lock is false, THEN the scheduler invokes the pipeline with the oldest unprocessed record
- [ ] AC-02.5: GIVEN the app crashed while the lock was held, WHEN the app relaunches, THEN the global lock starts as false and the previously locked item becomes eligible for processing

---

### US-03 — Voice memo is transcribed
As the app,
I want to transcribe a voice memo's audio into text,
So that the transcript can be passed to downstream classification and routing.

**Acceptance Criteria**
- [ ] AC-03.1: GIVEN a memo is selected by the scheduler, WHEN transcription begins, THEN the global lock is set to true before any processing starts
- [ ] AC-03.2: GIVEN a memo file path, WHEN the transcription stage runs, THEN the audio file is transcribed via speech-to-text and the result (transcript text + file path) is emitted
- [ ] AC-03.3: GIVEN transcription completes, WHEN the result is emitted, THEN the global lock remains true and date processed remains null (stage 2 is responsible for completing the record)
- [ ] AC-03.4: GIVEN the audio file cannot be read or transcription fails, WHEN the error occurs, THEN the failure is logged, the lock is released, and date processed is set to the current timestamp (permanent failure — prevents infinite re-processing)
- [ ] AC-03.5: GIVEN the audio file contains only silence or noise, WHEN transcription completes with an empty string result, THEN the empty transcript and file path are emitted as a successful result (no error is logged, lock behavior follows the success path)

---

## Data Model

The datastore tracks each voice memo through the processing pipeline:

- **File path**: Full path to the `.m4a` file — serves as the unique identifier (voice memo filenames contain UUIDs)
- **Date created**: Timestamp when the record was inserted (not the file's filesystem date)
- **Date processed**: Timestamp when stage 2 completes processing, or when a permanent failure occurs. Null while unprocessed or in-progress.
- **Global processing lock**: A single boolean flag (not per-record). Starts `false` on every app launch. Set to `true` when the pipeline begins working on a memo. Released by stage 2 on success, or by the pipeline on permanent failure.

---

## Edge Cases

- **App crash during transcription**: Lock resets to `false` on next launch. The same memo is picked up again since its `dateProcessed` is still null. This is intentional — a crash is not a permanent failure.
- **Duplicate file events from watcher**: The watcher's in-memory dedup handles most duplicates within a session. The datastore's file-path uniqueness handles cross-session and edge-case duplicates.
- **Voice memo file deleted before transcription**: The file path is in the datastore but the file no longer exists on disk. Treated as a permanent failure — logged, `dateProcessed` set, lock released.
- **Very long audio file**: Transcription may take longer than the 30-second scheduler interval. Not a problem — the global lock prevents the scheduler from picking another item while transcription is in progress. The scheduler's lock check and record selection should be treated as atomic — if the timer fires while a previous cycle's pipeline work is in progress, the lock gate prevents any overlap.
- **iCloud renames a file (conflict resolution)**: The renamed file will be treated as a new memo. This is a known limitation of path-based deduplication in V1.
- **Datastore is unwritable** (e.g., disk full): New records cannot be inserted. The consumer should log the error. The spec says "never process memos if the dedup store cannot be written" — so the system should refuse to proceed rather than risk duplicates.
- **Multiple rapid file events**: Several memos arrive in quick succession. All are recorded in the datastore immediately. The scheduler processes them one at a time, oldest first.
- **Empty transcript**: Speech-to-text returns an empty string (e.g., recording is silence or noise). Still emitted to stage 2 — classification is not this stage's responsibility.

---

## Success Criteria

1. 100% of voice memo events from the watcher result in a datastore record when the store is writable (no silent drops)
2. Zero duplicate records for the same file path across any number of app restarts
3. 100% of crash-interrupted memos (dateProcessed is null, lock was held) are re-attempted on the next launch cycle
4. Transcription produces a non-null result (possibly empty string) for every processable audio file
5. 100% of permanent failures result in dateProcessed being set and the lock being released within the same cycle

---

## Dependencies & Assumptions

**Dependencies**
- `VoiceMemoWatcher` and its `AsyncStream<VoiceMemoEvent>` (existing, in `Libraries/Sources/Core/`)
- macOS `SpeechAnalyzer` API availability (macOS 26+)
- Project spec: spec.md

**Assumptions**
- Voice memo `.m4a` filenames contain a UUID or unique string, making the full file path a reliable dedup key
- `SpeechAnalyzer` can process `.m4a` files directly without format conversion
- A single global lock (serial processing) is sufficient throughput for the expected volume of voice memos
- Stage 2 will be responsible for setting `dateProcessed` and releasing the global lock on successful completion. Stage 1 handles these only on permanent failure (file missing, transcription error)
- The spec's "no retry" rule applies to processing failures, not to crash recovery — a crash-interrupted memo should be re-attempted

---

## Open Questions

**All open questions were resolved during the interview.**

- [x] Should transcription use embedded .m4a transcript extraction or speech-to-text?
  - Context: The spec originally planned to extract transcripts embedded by the Voice Memos app. The macOS SpeechAnalyzer API offers an alternative that works even when Voice Memos hasn't generated a transcript.
  - Options considered: (a) Extract embedded transcript from .m4a metadata, (b) Use SpeechAnalyzer speech-to-text on the audio
  - Decision needed by: Before implementation
  - Decision: Use SpeechAnalyzer speech-to-text. The spec should be updated.
  - Reasoning: Deliberate pivot — more reliable than depending on Voice Memos to have generated an embedded transcript.

- [x] Does the pipeline need to work on macOS 15-25, or is macOS 26+ acceptable?
  - Context: SpeechAnalyzer requires macOS 26+. The project's deployment target is macOS 15.0. This means the transcription stage cannot function on macOS 15-25.
  - Options considered: (a) Require macOS 26+ for the pipeline, (b) Provide a fallback transcription mechanism for older macOS, (c) Abstract behind a protocol and defer the fallback
  - Decision needed by: Before implementation
  - Decision: Use SpeechAnalyzer (macOS 26+). The transcription stage will be behind a protocol abstraction; the concrete implementation will require macOS 26+. No fallback for macOS 15-25 in this plan.
  - Reasoning: The user targets macOS 26+. A fallback can be added later behind the same protocol if needed.

- [x] Should the processing lock be per-record or global?
  - Context: A per-record lock allows concurrent processing; a global lock enforces serial processing.
  - Options considered: (a) Per-record lock, (b) Global lock
  - Decision needed by: Before implementation
  - Decision: Global lock. One memo at a time.
  - Reasoning: Serial processing is simpler and sufficient for the expected volume (a few memos per day).

- [x] Should the scheduler run continuously or only when there are items to process?
  - Context: Original request had the scheduler enable/disable based on queue state. Follow-up clarified always-on.
  - Options considered: (a) Enable/disable based on queue state, (b) Always running, checks condition each cycle
  - Decision needed by: Before implementation
  - Decision: Always running. Checks the condition (unprocessed items + lock free) every 30 seconds.
  - Reasoning: Simpler — no enable/disable orchestration needed. Also handles crash recovery naturally since the lock resets on launch.

- [x] What polling interval should the scheduler use?
  - Context: The scheduler checks for unprocessed items on a fixed interval. Too frequent wastes CPU; too infrequent delays processing.
  - Options considered: 10s, 30s, 60s, event-driven
  - Decision needed by: Before implementation
  - Decision: 30 seconds.
  - Reasoning: Low-overhead for a few memos per day. Can be tuned later — the interval will be injectable for testability.

- [x] What happens to a memo that was in-progress when the app crashes?
  - Context: The spec says "each memo attempted once, no automatic retry." A crash during transcription leaves the record with dateProcessed = null.
  - Options considered: (a) Leave it stuck forever (strict "once" interpretation), (b) Re-attempt on next launch (crash ≠ failure)
  - Decision needed by: Before implementation
  - Decision: Re-attempt. The global lock resets to false on every app launch, making the item eligible again.
  - Reasoning: A crash is not a processing failure — it's an infrastructure interruption. The "no retry" rule applies to transcription errors, not crashes.

---

## Out of Scope (Clarification)

- **LLM classification and routing to Reminders/Calendar/Notes** — this is stage 2 of the pipeline, to be planned separately. The transcript emission point is the handoff boundary.
- **Embedded transcript extraction from .m4a metadata** — originally planned in the spec, deliberately replaced by `SpeechAnalyzer` speech-to-text. The spec should be updated to reflect this decision.
- **Menu bar status display for the processing queue** — useful but not part of this pipeline scaffolding work.
- **Remote LLM fallback for transcription** — `SpeechAnalyzer` is on-device only. If a fallback transcription path is needed for macOS 15-25, that's a separate decision.
