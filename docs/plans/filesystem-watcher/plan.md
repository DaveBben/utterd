# Filesystem Watcher Plan

**Date**: 2026-03-26
**Status**: Complete
**Author**: Dave
**Project Spec**: spec.md

---

## Why This Exists

The voice memo triage pipeline has no way to know when a new memo arrives. Without a detection mechanism monitoring the iCloud Voice Memos sync directory, the entire pipeline — classification, extraction, routing — cannot start. This is the first stage of the pipeline and the trigger for everything downstream.

---

## Scope

### In
- A reusable directory watcher that detects new `.m4a` files appearing in a monitored directory
- Emits file URLs via an event stream as they are detected
- Accepts the watched directory path as a parameter (not hardcoded)
- Coalesces multiple OS-level events for the same file path into a single emission (intra-session event dedup)
- Lives in a library target for isolated testability

### Out (explicitly)
- Copying files to a temp location — that is the next pipeline stage
- Cross-session dedup checking — whether a file was processed in a prior app session is a downstream concern
- Processing pre-existing files at startup — only files that appear after the watcher starts are emitted
- Watching subdirectories recursively — Voice Memos stores `.m4a` files flat in the Recordings directory
- Monitoring for file deletions or modifications — only new file creation events
- UI integration or menu bar status — separate concern, wired later

---

## User Stories

### US-01 — Detect new voice memos
As the triage pipeline,
I want to be notified when a new `.m4a` file appears in the watched directory,
So that I can begin processing the memo.

**Acceptance Criteria**
- [ ] AC-01.1: GIVEN the watcher is running on a directory, WHEN a new `.m4a` file is created in that directory, THEN the file's URL is emitted on the event stream within 5 seconds
- [ ] AC-01.2: GIVEN the watcher is running, WHEN a non-`.m4a` file is created in the directory (e.g., `.json`, `.plist`), THEN no event is emitted
- [ ] AC-01.3: GIVEN the watcher is running, WHEN multiple `.m4a` files are created in quick succession, THEN each file's URL is emitted exactly once

### US-02 — Ignore pre-existing files
As the triage pipeline,
I want the watcher to only emit events for files that appear after it starts,
So that I don't reprocess memos that were already handled in a prior session.

**Acceptance Criteria**
- [ ] AC-02.1: GIVEN a directory containing existing `.m4a` files, WHEN the watcher starts, THEN no events are emitted for those existing files

### US-03 — Start and stop cleanly
As the app lifecycle owner,
I want to start and stop the watcher without resource leaks,
So that the app can run indefinitely without degradation.

**Acceptance Criteria**
- [ ] AC-03.1: GIVEN a running watcher, WHEN the consumer stops listening, THEN the watcher stops monitoring and releases its file system resources
- [ ] AC-03.2: GIVEN a stopped watcher, WHEN no references remain, THEN no background threads, file descriptors, or event streams are leaked

---

## Edge Cases

- **File written in multiple chunks (slow iCloud sync)**: A large `.m4a` file syncing from iCloud may trigger multiple OS-level events as it is written incrementally. The watcher coalesces these into a single emission per file path (this is the intra-session dedup listed in Scope In).
- **Watched directory does not exist at start**: The watcher should report an error rather than silently doing nothing.
- **Watched directory is deleted while running**: The watcher should terminate its event stream gracefully rather than crash.
- **File created as `.m4a` then immediately renamed away**: The watcher emits based on creation events matching `.m4a`. If a file is created as `.m4a` and subsequently renamed or deleted, the already-emitted event is not retracted — downstream stages handle files that no longer exist at their original path.
- **Rapid burst of files**: If dozens of memos sync at once (e.g., phone reconnects after offline period), all `.m4a` files should be emitted without dropping any.
- **Permissions error on directory**: If the app lacks read access to the directory, the watcher should report the error, not silently fail.
- **Empty directory at startup**: The watcher starts successfully on an empty directory and emits events normally when the first `.m4a` file later appears.

---

## Success Criteria

1. 100% of `.m4a` files created after watcher start are emitted on the event stream within 5 seconds of file creation
2. Zero duplicate emissions for the same file path during a single watcher session
3. Zero emissions for pre-existing files at startup
4. Zero leaked file descriptors or background threads after watcher cancellation, verified by test
5. 100% of error conditions (missing directory, deleted directory, permissions failure) produce a reportable error rather than silent failure
6. All watcher tests pass in the library test suite without requiring the full app build

---

## Dependencies & Assumptions

**Dependencies**
- macOS file system change notification APIs — available on all supported macOS versions (15+)
- Swift concurrency primitives for event streaming
- Library target build infrastructure (already exists)

**Assumptions**
- The iCloud Voice Memos sync directory stores `.m4a` files flat (not in subdirectories) — if Apple changes this layout, the watcher would need recursive support
- macOS file system change notifications fire reliably for files written by iCloud sync — if iCloud uses atomic moves from a staging directory, the OS still reports the event for the final location. This was confirmed during interview; if it turns out to be false for a specific macOS version, the approach may need revisiting
- A single watched directory is sufficient — the app does not need to watch multiple directories simultaneously (though the class design does not prevent it)

---

## Open Questions

None — all resolved during interview.

---

## Out of Scope (Clarification)

- **Debounce/coalescing for partially written files** — discussed because iCloud sync may write files incrementally, but the watcher's job is detection only. If a downstream stage needs to wait for a file to finish writing, that is the responsibility of the copy stage (which can check file stability before copying). The watcher emits the event; consumers decide when to act.
- **Retry on transient directory access failures** — discussed because the Recordings directory lives on iCloud-synced storage. The spec says no automatic retry (each memo attempted once), and the watcher itself is not a processing stage — it just detects. If the directory becomes inaccessible, the watcher terminates its stream and the app surfaces an error.
