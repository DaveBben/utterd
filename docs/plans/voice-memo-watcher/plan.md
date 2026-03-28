# Voice Memo File Watcher Plan

**Date**: 2026-03-27
**Status**: Approved
**Author**: Dave + Claude
**Project Spec**: [spec.md](../../../spec.md)

---

## Why This Exists

Voice memos recorded on iPhone sync to the Mac via iCloud, but nothing in the system
detects when a new memo arrives. Without a watcher, the entire triage pipeline has no
trigger — memos sit in the sync folder unprocessed until someone manually intervenes.
This is the foundational "front door" that every downstream stage (transcript extraction,
classification, routing) depends on.

---

## Scope

### In
- Monitor the iCloud Voice Memos sync folder for newly arriving `.m4a` files
- Emit an observable event stream that downstream components can consume for each new, fully-synced voice memo
- Log each detection event with file identity details
- On application start, catalog existing files without emitting events for them
- Treat files as fully synced only when they are not `.icloud` placeholders and exceed 1024 bytes
- Handle folder unavailability gracefully (retry without crashing)

### Out (explicitly)
- Transcript extraction from `.m4a` files — separate pipeline stage
- Deduplication store — downstream consumers handle whether a file was already processed
- Processing, classifying, or routing memos — this is detection only
- Modifying, moving, or deleting voice memo files — read-only access
- UI for showing watcher status — operability features come later
- Permission onboarding UI (alerts, deep-links to System Settings) — the watcher detects and logs permission errors, but guiding the user to grant access is a separate concern

---

## User Stories

### US-01 — Automatic detection of new voice memos
As the app daemon,
I want to be notified when a new voice memo finishes syncing to the local folder,
So that the triage pipeline can begin processing it without manual intervention.

**Acceptance Criteria**
- [ ] AC-01.1: GIVEN the watcher is running and the sync folder exists, WHEN a new `.m4a` file appears that is > 1024 bytes and is not an `.icloud` placeholder, THEN an event is emitted containing the file's URL
- [ ] AC-01.2: GIVEN the watcher is running, WHEN a new `.m4a` file appears but is an `.icloud` placeholder or ≤ 1024 bytes, THEN no event is emitted until the file meets the fully-synced criteria
- [ ] AC-01.3: GIVEN the watcher is running, WHEN a file transitions from `.icloud` placeholder to a fully-synced `.m4a` (> 1024 bytes), THEN exactly one event is emitted for that file
- [ ] AC-01.4: GIVEN the watcher detects a fully-synced file, WHEN the event is emitted, THEN the file name and size are written to the log
- [ ] AC-01.5: GIVEN the watcher has already emitted an event for a file at path X, WHEN additional filesystem events occur for path X, THEN no additional events are emitted for that path
- [ ] AC-01.6: GIVEN the watcher is running, WHEN 5 `.m4a` files appear in the sync folder within 1 second (all > 1024 bytes, not placeholders), THEN exactly 5 events are emitted, one per file
- [ ] AC-01.7: GIVEN the watcher is running, WHEN a `.txt`, `.jpg`, or other non-`.m4a` file appears in the sync folder, THEN no event is emitted
- [ ] AC-01.8: GIVEN the watcher is running, WHEN the sync folder is deleted or becomes inaccessible, THEN the watcher logs an error, continues running without crashing, and checks for the folder's reappearance at an interval between 5 and 60 seconds
- [ ] AC-01.9: GIVEN the watcher is checking for a missing folder, WHEN the folder reappears, THEN monitoring resumes and new files are detected normally

### US-02 — Ignore pre-existing memos on startup
As the app daemon,
I want the watcher to skip voice memos already present when the app launches,
So that only newly arriving memos trigger the pipeline.

**Acceptance Criteria**
- [ ] AC-02.1: GIVEN the sync folder contains 5 `.m4a` files when the watcher starts, WHEN the watcher begins monitoring, THEN zero events are emitted for those 5 files
- [ ] AC-02.2: GIVEN the watcher has started and cataloged existing files, WHEN a 6th `.m4a` file appears, THEN exactly one event is emitted for the new file
- [ ] AC-02.3: GIVEN the sync folder contains a file `memo.m4a` that is 512 bytes (mid-sync) when the watcher starts, WHEN the file later grows to 2048 bytes, THEN exactly one event is emitted for that file

### US-03 — Listener consumption of watcher events
As a downstream pipeline component,
I want to observe the watcher's event stream,
So that I can react to each new memo independently.

Each emitted event contains at minimum: the file URL and the file size in bytes at the time of detection. The event stream is an asynchronous sequence that supports multiple concurrent consumers.

**Acceptance Criteria**
- [ ] AC-03.1: GIVEN a listener is consuming the watcher's asynchronous event stream, WHEN the watcher emits an event, THEN the listener receives the file URL and file size in bytes
- [ ] AC-03.2: GIVEN multiple listeners are each consuming their own view of the event stream, WHEN the watcher emits an event, THEN all listeners receive it

### US-04 — Watcher handles missing sync folder on startup
As the app daemon,
I want the watcher to start gracefully even if the sync folder doesn't exist yet,
So that the app doesn't crash if iCloud hasn't synced or the user hasn't recorded any memos.

**Acceptance Criteria**
- [ ] AC-04.1: GIVEN the sync folder does not exist when the watcher starts, WHEN the watcher is initialized, THEN it logs a warning and checks for the folder's appearance at an interval between 5 and 60 seconds without crashing
- [ ] AC-04.2: GIVEN the watcher is waiting for a missing folder, WHEN the folder is created, THEN the watcher begins monitoring it and detects new files normally

### US-05 — Watcher detects missing read permission
As the app daemon,
I want the watcher to detect when it lacks permission to read the sync folder,
So that the error is logged and the app can inform the user rather than silently failing.

**Acceptance Criteria**
- [ ] AC-05.1: GIVEN the sync folder exists but the app lacks read permission, WHEN the watcher attempts to start monitoring, THEN it logs an error identifying the permission issue and does not emit any file events
- [ ] AC-05.2: GIVEN the watcher has logged a permission error, WHEN the app subsequently gains read permission (e.g., user grants Full Disk Access), THEN the watcher detects the change, begins monitoring, and logs that monitoring has started

---

## Edge Cases

- **`.icloud` placeholder arrives, then real file follows**: The watcher ignores the placeholder, detects the real file only after it exceeds 1024 bytes, and emits exactly one event.
- **File arrives but stays ≤ 1024 bytes**: No event is emitted. This handles corrupted or truncated syncs.
- **Boundary: file at exactly 1024 bytes**: No event emitted. The threshold is strictly greater than 1024 bytes.
- **Rapid burst of new files**: Each file gets its own event; no events are lost or merged.
- **Non-`.m4a` files appear in the folder**: Ignored entirely — only `.m4a` files trigger events.
- **App restarts while files are mid-sync**: On restart, the watcher catalogs whatever is present (including partial syncs). If a file finishes syncing after restart, it is detected as new content at an existing path and emits an event once it meets the size threshold.
- **Same file path receives multiple filesystem events**: Repeated write events for the same path are coalesced — at most one event per file path after it first meets the fully-synced criteria.
- **File deletion from the watched folder**: If a previously-cataloged file is deleted (e.g., user deletes a memo from iPhone), the watcher silently ignores the deletion event without crashing or emitting an error.
- **Sync folder disappears mid-operation**: The watcher enters a retry/recovery state, logs the error, and resumes monitoring when the folder reappears.
- **App lacks read permission for the sync folder**: The watcher logs an error identifying the permission issue. No events are emitted. If permission is later granted, the watcher recovers and begins monitoring.

---

## Success Criteria

1. 100% of fully-synced voice memos arriving after watcher start produce exactly one event each
2. Zero events emitted for files present before watcher start
3. Zero events emitted for `.icloud` placeholders or files ≤ 1024 bytes
4. After processing 100 file events in sequence, watcher memory footprint does not grow beyond its post-startup baseline by more than 10%
5. Detection-to-event latency < 5 seconds after file meets the fully-synced criteria (integration tests may use a 10-second tolerance for CI variability)

---

## Dependencies & Assumptions

**Dependencies**
- macOS file system event APIs for directory monitoring
- iCloud sync delivering `.m4a` files to `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`
- App must have permission to read the Voice Memos group container directory

**Assumptions**
- Voice memos are only ever added to the folder — never renamed, moved, or deleted by the system (though deletion is handled defensively)
- A fully-synced `.m4a` file will always exceed 1024 bytes (voice memos have audio content + metadata)
- iCloud sync replaces `.icloud` placeholders with the real file at the same logical path
- The sync folder path (`~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`) is stable across macOS versions (group container convention)
- The app will have the necessary entitlements/permissions to access the group container (may require Full Disk Access or a user-granted folder permission depending on sandbox configuration)
- "1 KB" throughout this plan means 1024 bytes (binary kilobyte)
- The watcher's seen-file set is in-memory only; on restart, existing files are cataloged per US-02, which prevents re-emission. Cross-restart deduplication is the responsibility of downstream consumers.
- The watcher treats any filesystem event at a path as a potential readiness change and re-evaluates the file against the fully-synced criteria. This approach is resilient to whether iCloud uses rename, delete+create, or in-place replacement.

---

## Open Questions

- [x] Should the watcher emit events for files already present at startup?
  - Context: Emitting for all files on startup would reprocess the entire history; skipping them means only new arrivals are handled
  - Options considered: Emit for all, emit for none, emit only for files newer than a timestamp
  - Decision needed by: Before plan approval
  - Decision: No — catalog existing files silently on start
  - Reasoning: The pipeline is for newly arriving memos; historical processing is not a goal

- [x] Who owns deduplication — the watcher or downstream consumers?
  - Context: The watcher could check a dedup store before emitting, or emit freely and let consumers filter
  - Options considered: Watcher checks dedup store, watcher emits freely, hybrid
  - Decision needed by: Before plan approval
  - Decision: Downstream — the watcher is purely an event emitter
  - Reasoning: Keeps the watcher simple and single-responsibility; dedup is a pipeline concern

- [x] What defines a "fully synced" file?
  - Context: iCloud uses `.icloud` placeholders that get replaced with real files; emitting too early means consumers get unusable files
  - Options considered: Any .m4a file, non-zero size, > 1 KB, check extended attributes
  - Decision needed by: Before plan approval
  - Decision: Not an `.icloud` placeholder AND file size > 1024 bytes
  - Reasoning: 1 KB threshold filters out stubs while being simple to check; all real voice memos exceed this easily

---

## Out of Scope (Clarification)

- **Persistent dedup store** — discussed because the spec includes deduplication as a pipeline concern, but this watcher is purely an event emitter. Dedup is a downstream responsibility.
- **Monitoring multiple folders** — discussed implicitly, but only the single iCloud Voice Memos sync folder is relevant for this product.
- **Health check / status reporting UI** — the watcher logs events, but exposing watcher state in the menu bar is a separate operability feature.
- **Permission onboarding flow** — discussed because the watcher needs Full Disk Access to read the group container. The watcher detects and logs the permission error (US-05), but the UI to alert the user and guide them to System Settings is a separate plan.
