# Voice Memo File Watcher — Task Breakdown

**Plan**: [plan.md](plan.md)
**Date**: 2026-03-27
**Status**: In Progress

---

## Prerequisites

- **App Sandbox vs Voice Memos Access**: The current entitlements (`Utterd/Resources/Utterd.entitlements`) enable `com.apple.security.app-sandbox` with only network-client permission. A sandboxed app cannot access `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings` — this is Apple's group container and is not joinable by third-party apps. Before this watcher can be validated against the real directory, the sandbox must be disabled (appropriate for a non-App-Store single-user daemon) or user-granted folder access via security-scoped bookmarks must be implemented. **This is not a task in this plan** — it is a separate entitlements/permissions concern. All tasks here use temporary directories for testing and are valid regardless of the sandbox decision.

---

## Key Decisions

- **Module location: `Libraries/Sources/Core/`** — The watcher is domain infrastructure, not UI. Placing it in the local SPM package enables fast `swift test` without Xcode, aligns with the project's modularity goal (spec.md architecture decision), and keeps the `Utterd/` target focused on app-layer concerns. Alternative considered: `Utterd/Core/` — rejected because it couples the watcher to the app target and prevents independent testing.

- **Actor isolation: `@MainActor` for watcher state, background queues for FS monitoring** — The watcher's state management (seen-set, continuation registry, lifecycle) is lightweight and benefits from the same isolation model the codebase already uses. The actual filesystem monitoring (FSEvents) runs on its own dispatch queue regardless — the `@MainActor` annotation only governs the watcher's state, not the monitoring work. This avoids the `onTermination` actor-hop race condition: when an `AsyncStream` consumer cancels, the `onTermination` closure runs on an arbitrary executor and must dispatch back to remove the continuation. With `@MainActor`, this uses `DispatchQueue.main.async` (the documented SE-0468 pattern). With a custom actor, it requires an unstructured `Task` hop that races with deinitialization. Note: `@MainActor` on a library type constrains callers to `await` into it from non-main contexts, but this is acceptable since the watcher's state operations are trivial (no blocking work), and all current consumers are `@MainActor` UI models. If future non-UI consumers need direct access, this decision can be revisited. Alternative considered: custom `actor` — rejected due to the `onTermination` race.

- **Event delivery: `AsyncStream<VoiceMemoEvent>` with broadcast** — Swift's native `AsyncStream` fits the project's modern-Swift-first approach and avoids a Combine dependency. To support multiple concurrent consumers (AC-03.2), the watcher exposes a method that returns a new `AsyncStream` for each caller, backed by a shared continuation registry. Each stream uses `.bufferingOldest(16)` buffering policy — this prevents unbounded memory growth from slow consumers while preserving event ordering. Alternative considered: `PassthroughSubject` from Combine — rejected because the rest of the codebase uses async/await, not Combine.

- **Filesystem monitoring: FSEvents C API (`FSEventStreamCreate` from CoreServices) with `kFSEventStreamCreateFlagFileEvents`** — `DispatchSource.makeFileSystemObjectSource` uses kqueue, which fires on directory entry changes (add/remove/rename) but NOT on in-place file content growth. iCloud sync may write files in-place rather than using atomic replace, so kqueue would miss mid-sync files growing past the 1024-byte threshold (violating AC-01.3 and AC-02.3). The FSEvents C API with the `kFSEventStreamCreateFlagFileEvents` flag reports per-file content modifications including individual changed file paths, which is the correct tool. `import CoreServices` works directly in SPM packages targeting macOS — no additional dependency needed. Note: wrapping `FSEventStreamCreate` in Swift requires C function pointers, `UnsafeMutableRawPointer` context passing, and manual stream lifecycle management — Task 1 should reference existing open-source wrappers (e.g., FSEventsWrapper, EonilFSEvents) as implementation guides. Alternative considered: `DispatchSource` — rejected because it cannot detect in-place file growth.

- **DirectoryMonitor stream element type: `AsyncStream<Set<URL>>`** — The monitor's event stream carries the set of changed file URLs per notification, matching FSEvents' native output (which reports changed paths). This allows the watcher to check only the changed files rather than rescanning the entire directory on every notification. The `MockDirectoryMonitor.emit()` method takes a `Set<URL>` parameter so tests can specify exactly which file(s) changed. Alternative considered: `AsyncStream<Void>` (bare notification forcing full directory scan) — rejected as inefficient, especially for the burst scenario.

- **Testability via protocol: `DirectoryMonitor` protocol** — FSEvents cannot be unit-tested deterministically. A `DirectoryMonitor` protocol abstracts the raw filesystem monitoring. Tests inject a `MockDirectoryMonitor` that emits synthetic events. This enables fast, deterministic tests in `Libraries/Tests/CoreTests/`. Alternative considered: integration-only testing with temp directories — rejected because it would be slow, non-deterministic, and require filesystem cleanup.

- **Testability for filesystem operations: `FileSystemChecker` protocol** — The watcher needs to check directory existence, readability, enumerate directory contents, and stat individual files. Mocking `FileManager` directly violates "don't mock what you don't own." A `FileSystemChecker` protocol abstracts all filesystem queries: `directoryExists(at:)`, `isReadable(at:)`, `contentsOfDirectory(at:) -> [URL]`, and `fileSize(at:) -> Int64?`. Tests inject a `MockFileSystemChecker` with configurable return values. Alternative considered: using real temp directories with `chmod` — rejected because permission manipulation is fragile and may require elevated privileges.

- **Testability for logging: `WatcherLogger` protocol** — Tasks 4a and 5 require verifiable logging (AC-01.4, AC-01.8, AC-04.1, AC-05.1). The production implementation uses `os.Logger` with `Logger(subsystem: "com.bennett.Utterd", category: "VoiceMemoWatcher")`, which integrates with Console.app. Tests inject a `MockWatcherLogger` that captures log messages for assertion. Alternative considered: asserting on `os.Logger` output directly — rejected because `os.Logger` output is not capturable in unit tests.

- **Seen-set data structure: `[URL: Int64?]` (path + last-known-size)** — Tracking path only is insufficient for the mid-sync scenario (AC-02.3): a file cataloged at 512 bytes on startup must emit an event when it later grows to 2048 bytes. The seen-set maps each URL to its last-known size at the time it was evaluated. A `nil` size means the file was cataloged but has not yet qualified (either too small or not yet evaluated). Once a file qualifies and an event is emitted, the size is recorded and no further events are emitted for that path regardless of subsequent size changes. Alternative considered: `Set<URL>` (path only) — rejected because it cannot distinguish "seen but unqualified" from "seen and emitted."

- **Polling for missing/permission-denied folder with exponential backoff** — When the sync folder is missing or unreadable, the watcher enters a polling state starting at 5 seconds, doubling each cycle up to 60 seconds (5s → 10s → 20s → 40s → 60s → 60s…). This stays within the plan's 5–60 second range and reduces unnecessary work for genuinely missing folders. The backoff schedule is injectable for testing via a `Clock` parameter (type: `any Clock<Duration>`, defaulting to `ContinuousClock()`). Tests can pass a custom clock implementation that resolves sleep to zero delay for instant state transitions. Alternative considered: fixed 10-second interval — rejected as wasteful for long-missing folders.

---

## Layers

| Layer | Covers | Key directories/files |
|-------|--------|-----------------------|
| Core (Library) | Watcher service, event types, protocols, qualifier, monitor implementation | `Libraries/Sources/Core/`, `Libraries/Tests/CoreTests/` |

This is a single-layer change. All files live in the `Libraries/` SPM package. No app-target files are created or modified — integration with `AppState` and UI is explicitly out of scope (plan.md: Out section). Tasks run sequentially within this single layer.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-01.1: New .m4a > 1024 bytes, not placeholder → event emitted | Task 2, Task 3 |
| AC-01.2: Placeholder or ≤ 1024 bytes → no event | Task 2 |
| AC-01.3: File transitions from placeholder to fully-synced → exactly one event | Task 4a |
| AC-01.4: Event includes file name and size in log | Task 4a |
| AC-01.5: No duplicate events for same path | Task 3 |
| AC-01.6: 5 files in 1 second → 5 events | Task 4a |
| AC-01.7: Non-.m4a files → no event | Task 2 |
| AC-01.8: Folder deleted/inaccessible → log error, retry 5–60s | Task 5 |
| AC-01.9: Folder reappears → monitoring resumes | Task 5 |
| AC-02.1: Existing files at startup → zero events | Task 3 |
| AC-02.2: New file after startup → one event | Task 3 |
| AC-02.3: Mid-sync file at startup, later grows → one event | Task 4a |
| AC-03.1: Listener receives file URL and size | Task 2 (event type), Task 3 (emission) |
| AC-03.2: Multiple listeners each receive event | Task 6 |
| AC-04.1: Missing folder at start → log warning, poll 5–60s | Task 5 |
| AC-04.2: Missing folder appears → monitoring begins | Task 5 |
| AC-05.1: No read permission → log error, no events | Task 5 |
| AC-05.2: Permission later granted → monitoring starts | Task 5 |
| Edge: .icloud placeholder then real file | Task 4a |
| Edge: File stays ≤ 1024 bytes | Task 2 |
| Edge: Exactly 1024 bytes → no event | Task 2 |
| Edge: Rapid burst of files | Task 4a |
| Edge: Non-.m4a files ignored | Task 2 |
| Edge: App restart with mid-sync files | Task 4a |
| Edge: Multiple FS events for same path coalesced | Task 3 |
| Edge: File deletion from watched folder | Task 4a |
| Edge: Sync folder disappears mid-operation | Task 5 |
| Edge: No read permission | Task 5 |
| Success: exactly-once emission | Task 3, Task 4a |
| Success: zero events for pre-existing files | Task 3 |
| Success: zero events for placeholders/small files | Task 2 |
| SC-4: Memory footprint ≤ 10% growth after 100 events | Deferred to a future plan — requires profiling tooling outside unit tests. The seen-set grows linearly (~80 bytes/entry); at 10 memos/day, annual growth is ~285 KB (negligible). The set resets on restart. A retention policy can be added if the watcher is repurposed for higher-volume directories. This deferral should be reflected in plan.md's Out of Scope section when the task file is approved. |
| SC-5: Detection latency < 5s | Task 1 (integration test validates FSEvents delivery latency) |

---

## Tasks

### Task 0: Define Contracts & Interfaces

**Layer:** Core (Library)

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoEvent.swift` ← create
- `Libraries/Sources/Core/DirectoryMonitor.swift` ← create
- `Libraries/Sources/Core/FileSystemChecker.swift` ← create
- `Libraries/Sources/Core/WatcherLogger.swift` ← create
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← create (public interface only)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/Core.swift` — understand the existing module structure and public API surface
- `Libraries/Package.swift` — confirm target layout; Swift PM recursively includes `Tests/CoreTests/**/*.swift` so the `Mocks/` subdirectory will be picked up automatically
- `spec.md` lines 53–69 — understand pipeline architecture and where the watcher fits

**Steps:**

1. [ ] Define `VoiceMemoEvent` struct: `public`, `Sendable`, `Equatable`, with `fileURL: URL` and `fileSize: Int64`
2. [ ] Define `DirectoryMonitor` protocol: `start()` begins monitoring a directory, `stop()` ends it, events delivered as `AsyncStream<Set<URL>>` (set of changed file URLs per notification)
3. [ ] Define `FileSystemChecker` protocol: `directoryExists(at: URL) -> Bool`, `isReadable(at: URL) -> Bool`, `contentsOfDirectory(at: URL) -> [URL]`, `fileSize(at: URL) -> Int64?`
4. [ ] Define `WatcherLogger` protocol: `info(_: String)`, `warning(_: String)`, `error(_: String)`
5. [ ] Define `VoiceMemoWatcher` public interface: initializer accepting directory URL, `DirectoryMonitor`, `FileSystemChecker`, `WatcherLogger`, and `clock: any Clock<Duration>` (defaulting to `ContinuousClock()`); `start()`, `stop()`, `events() -> AsyncStream<VoiceMemoEvent>`
6. [ ] Create `MockDirectoryMonitor`: `emit(_ changedURLs: Set<URL>)` yields the set into the async stream; `failOnStart: Bool` to simulate start failure; `completeStream()` to finish the stream
7. [ ] Create `MockFileSystemChecker`: mutable `existsResult: Bool`, `readableResult: Bool`; mutable `directoryContents: [URL]` and `fileSizes: [URL: Int64]` for configurable return values
8. [ ] Create `MockWatcherLogger`: captures messages in `infos: [String]`, `warnings: [String]`, `errors: [String]` arrays
9. [ ] Verify all types compile: `cd Libraries && swift build`

**Acceptance Criteria:**

- GIVEN the `VoiceMemoEvent` struct, WHEN inspected, THEN it is `public`, `Sendable`, `Equatable`, and contains `fileURL: URL` and `fileSize: Int64`
- GIVEN the `DirectoryMonitor` protocol, WHEN read by a developer, THEN it defines `start()`, `stop()`, and an `events` property returning `AsyncStream<Set<URL>>` (set of changed file URLs)
- GIVEN the `FileSystemChecker` protocol, WHEN read by a developer, THEN it defines `directoryExists(at: URL) -> Bool`, `isReadable(at: URL) -> Bool`, `contentsOfDirectory(at: URL) -> [URL]`, and `fileSize(at: URL) -> Int64?`
- GIVEN the `WatcherLogger` protocol, WHEN read by a developer, THEN it defines `info(_:)`, `warning(_:)`, and `error(_:)` methods accepting `String`
- GIVEN the `VoiceMemoWatcher` interface, WHEN a consumer reads it, THEN they know how to initialize it (with a directory URL, a `DirectoryMonitor`, a `FileSystemChecker`, a `WatcherLogger`, and `clock: any Clock<Duration>`), start/stop it, and obtain an `AsyncStream<VoiceMemoEvent>` via `events()`
- GIVEN `MockDirectoryMonitor`, WHEN a test calls `emit(Set([url]))`, THEN the mock's async stream yields `Set([url])`; WHEN a test calls `completeStream()`, THEN the stream finishes; WHEN `failOnStart` is `true`, `start()` throws
- GIVEN `MockFileSystemChecker`, WHEN `existsResult = false`, THEN `directoryExists(at:)` returns `false`; WHEN `fileSizes[url] = 2048`, THEN `fileSize(at: url)` returns `2048`; WHEN `directoryContents = [url1, url2]`, THEN `contentsOfDirectory(at:)` returns `[url1, url2]`
- GIVEN `MockWatcherLogger`, WHEN a test triggers a warning log, THEN `warnings` array contains the message string
- GIVEN all contract and mock files, WHEN `cd Libraries && swift build` is run, THEN compilation succeeds with no errors

**Do NOT:**
- Implement any watcher logic (file filtering, seen-set tracking, polling) — only define the shapes
- Implement the production `FSEventsDirectoryMonitor` — that is Task 1
- Create the `VoiceMemoQualifier` — that is Task 2

---

### Task 1: Implement FSEvents DirectoryMonitor

**Layer:** Core (Library)

**Relevant Files:**
- `Libraries/Sources/Core/FSEventsDirectoryMonitor.swift` ← create
- `Libraries/Tests/CoreTests/FSEventsDirectoryMonitorTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/DirectoryMonitor.swift` — the protocol this implementation conforms to; note the stream carries `Set<URL>` of changed file paths (Task 0)
- `Libraries/Tests/CoreTests/CoreTests.swift` — understand existing test patterns (@Suite, @Test, #expect)
- `spec.md` lines 53–69 — understand where this monitor sits in the pipeline architecture

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Write minimal implementation to make tests pass
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Note:** This task creates **integration tests** that interact with the real filesystem via the FSEvents C API (`FSEventStreamCreate` from CoreServices with `kFSEventStreamCreateFlagFileEvents`). These tests are inherently slower and more timing-sensitive than the mock-based unit tests in other tasks. Set a low FSEvents latency (e.g., 0.1–0.5 seconds) in the implementation to minimize delivery delay. Use a 10-second test timeout for event delivery to accommodate CI variability. The implementation must use the FSEvents C API, NOT `DispatchSource.makeFileSystemObjectSource` — DispatchSource uses kqueue which cannot detect in-place file content growth. `import CoreServices` works directly in SPM packages — no dependency to add. Reference existing open-source FSEvents wrappers (FSEventsWrapper, EonilFSEvents) as implementation guides for the C API bridging.

**Acceptance Criteria:**

- GIVEN an `FSEventsDirectoryMonitor` initialized with a valid temporary directory path, WHEN `start()` is called and a new file is created in that directory, THEN the monitor's async stream emits a `Set<URL>` containing the new file's URL; the event should arrive within 5 seconds under normal conditions (test timeout is set to 10 seconds to account for CI variability)
- GIVEN an `FSEventsDirectoryMonitor` that is running, WHEN `stop()` is called, THEN the async stream completes (finishes) and no further events are delivered
- GIVEN an `FSEventsDirectoryMonitor`, WHEN `start()` is called with a path to a directory that does not exist, THEN it throws an error or the stream immediately completes without crashing

**Do NOT:**
- Implement file filtering (.m4a, size checks, placeholder detection) — the monitor reports raw directory changes; filtering is the watcher's job (Tasks 2–4a)
- Add polling/retry logic for missing folders — that is the watcher's responsibility (Task 5)
- Test with the real iCloud Voice Memos directory — use temporary directories only
- Use mocks or synthetic events — this is the one task where real filesystem I/O is intentional because we are verifying the FSEvents integration itself
- Use `DispatchSource` — it cannot detect in-place file growth; use `FSEventStreamCreate` from CoreServices

---

### Task 2: Implement File Qualification Logic

**Layer:** Core (Library)

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoQualifier.swift` ← create
- `Libraries/Tests/CoreTests/VoiceMemoQualifierTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the event type returned when a file qualifies (Task 0)
- `plan.md` lines 47–54, 99–107 — acceptance criteria and edge cases for file qualification rules

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Write minimal implementation to make tests pass
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a file URL with extension `.m4a` and file size 2048 bytes whose filename does not start with a dot, WHEN `qualifies(url:fileSize:)` is called, THEN it returns a `VoiceMemoEvent` with the file's URL and size
- GIVEN a file URL with extension `.m4a` and file size exactly 1024 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil` (threshold is strictly greater than 1024)
- GIVEN a file URL with extension `.m4a` and file size 512 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.m4a` and file size 0 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.txt` and file size 2048 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.jpg` and file size 2048 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with path component `.memo.m4a.icloud` (leading dot, `.icloud` extension — iCloud download placeholder convention), WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with path component `.voice_memo.m4a.icloud` (another iCloud placeholder variant), WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.m4a` and file size 1025 bytes whose filename does not start with a dot, WHEN `qualifies(url:fileSize:)` is called, THEN it returns a `VoiceMemoEvent` (just above threshold)

**Do NOT:**
- Access the filesystem to read file attributes — accept URL and file size as parameters so the logic is purely functional and testable without disk I/O
- Track seen files or deduplication — that is the watcher's job (Task 3)
- Add logging — that comes in Task 4a

---

### Task 3: Implement Core Watcher Logic (Startup Catalog and Basic Event Emission)

**Layer:** Core (Library)
**Blocked By:** Task 0, Task 2

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (add implementation to the interface from Task 0)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the public interface defined in Task 0
- `Libraries/Sources/Core/DirectoryMonitor.swift` — the protocol; stream carries `Set<URL>` of changed paths (Task 0)
- `Libraries/Sources/Core/FileSystemChecker.swift` — the protocol for filesystem queries including `contentsOfDirectory` and `fileSize` (Task 0)
- `Libraries/Sources/Core/VoiceMemoQualifier.swift` — the qualification logic used to filter files (Task 2)
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the event type emitted (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for injecting synthetic FS events with specific changed URLs (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock for configuring directory contents and file sizes (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift` — the mock for capturing log output (Task 0)
- `plan.md` lines 42–67 — US-01 and US-02 acceptance criteria

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Write minimal implementation to make tests pass
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Note:** The watcher's internal seen-set uses `[URL: Int64?]` — mapping file paths to their last-known size at emission time. `nil` means "cataloged but not yet qualified/emitted." On startup, the watcher calls `FileSystemChecker.contentsOfDirectory(at:)` to enumerate existing files and `fileSize(at:)` to get their sizes, populating the seen-set. When the `DirectoryMonitor` delivers a `Set<URL>` of changed paths, the watcher calls `fileSize(at:)` for each changed URL, runs the qualifier, and emits events for newly qualifying files.

**Acceptance Criteria:**

- GIVEN a `MockFileSystemChecker` configured with 3 qualifying `.m4a` files (each > 1024 bytes) in its `directoryContents` and `fileSizes`, WHEN `start()` is called and a consumer iterates the event stream and then the mock monitor emits a change for a NEW 4th qualifying file (also configured in `MockFileSystemChecker`), THEN exactly one event is emitted for the 4th file only — the 3 pre-existing files produce zero events (verifying startup catalog by observing that the pipeline works for new files but suppressed existing ones)
- GIVEN the watcher has started and cataloged existing files, WHEN the mock monitor emits a change containing a URL for a new qualifying `.m4a` file (configured in `MockFileSystemChecker` with size 2048), THEN exactly one `VoiceMemoEvent` is emitted with that file's URL and `fileSize: 2048`
- GIVEN the watcher has already emitted an event for a file URL, WHEN the mock monitor emits another change containing that same URL and `MockFileSystemChecker` still reports the same size, THEN no additional event is emitted (deduplication)
- GIVEN the watcher is running, WHEN the mock monitor emits a change containing a URL with extension `.txt` (configured in `MockFileSystemChecker`), THEN no event is emitted (qualifier rejects it)
- GIVEN the watcher is running, WHEN the mock monitor emits a change containing a URL for a `.m4a` file and `MockFileSystemChecker.fileSize` returns 512 for that URL, THEN no event is emitted (qualifier rejects it; file is tracked internally for future re-evaluation in Task 4a)
- GIVEN a consumer is iterating the watcher's event stream, WHEN `stop()` is called on the watcher, THEN the event stream completes and the `for await` loop exits cleanly

**Do NOT:**
- Implement folder-missing or permission-error recovery — that is Task 5
- Implement the broadcast/multi-listener pattern — that is Task 6; this task tests with a single consumer
- Implement mid-sync file growth re-evaluation, burst handling, deletion handling, or logging — that is Task 4a
- Use real filesystem monitoring — use `MockDirectoryMonitor` to inject synthetic change events and `MockFileSystemChecker` for all filesystem queries
- Add UI integration or modify any files in `Utterd/`

---

### Task 4a: Implement Mid-Sync Growth, Burst Handling, Logging, and Deletion Resilience

**Layer:** Core (Library)
**Blocked By:** Task 3

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (extend the implementation from Task 3)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherAdvancedTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the current watcher implementation from Task 3
- `Libraries/Sources/Core/VoiceMemoQualifier.swift` — the qualification logic (Task 2)
- `Libraries/Sources/Core/WatcherLogger.swift` — the logger protocol (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for injecting events with specific changed URLs (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock for configuring directory contents and file sizes (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift` — the mock for asserting on log output (Task 0)
- `plan.md` lines 42–54, 99–110 — acceptance criteria and edge cases

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Write minimal implementation to make tests pass
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN `MockFileSystemChecker` is configured with `memo.m4a` at 512 bytes in `directoryContents` at startup (cataloged with size `nil`), WHEN the watcher starts, then `MockFileSystemChecker.fileSizes` is updated to report `memo.m4a` at 2048 bytes, and the mock monitor emits a change containing `memo.m4a`'s URL, THEN exactly one `VoiceMemoEvent` is emitted with `fileSize: 2048`
- GIVEN the watcher has emitted an event for `memo.m4a` at 2048 bytes (recorded in seen-set), WHEN `MockFileSystemChecker` still reports 2048 and the mock monitor emits another change containing that URL, THEN no additional event is emitted
- GIVEN the watcher is running, WHEN the mock monitor emits 5 separate change notifications each containing the URL of a distinct new qualifying `.m4a` file (all configured in `MockFileSystemChecker` with sizes > 1024), THEN exactly 5 events are emitted, one per file, in the order the notifications were delivered
- GIVEN the watcher emits an event for a file, WHEN `MockWatcherLogger.infos` is inspected, THEN it contains a message including the file name and the file size in bytes
- GIVEN a previously cataloged file URL, WHEN `MockFileSystemChecker.fileSize` is updated to return `nil` for that URL (simulating deletion) and the mock monitor emits a change containing that URL, THEN the watcher does not crash and no error event or error log is emitted
- GIVEN the watcher's seen-set contains `.memo.m4a.icloud` (cataloged at startup or via a prior notification), WHEN `MockFileSystemChecker` is updated so `.memo.m4a.icloud` no longer appears in `directoryContents` and `memo.m4a` appears with size 2048, and the mock monitor emits a change containing `memo.m4a`'s URL, THEN exactly one event is emitted for `memo.m4a` — confirming the placeholder-to-real-file transition is treated as a new qualifying file

**Do NOT:**
- Modify startup catalog logic — that is finalized in Task 3
- Implement folder-missing or permission-error recovery — that is Task 5
- Implement multi-listener broadcast — that is Task 6
- Modify `VoiceMemoQualifier` — the filtering rules are fixed in Task 2
- Add UI integration or modify any files in `Utterd/`

---

### Task 5: Implement Folder Unavailability Handling (Missing, Permissions, Recovery)

**Layer:** Core (Library)
**Blocked By:** Task 4a

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (add folder availability checks and polling)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherFolderTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the current watcher implementation from Task 4a
- `Libraries/Sources/Core/DirectoryMonitor.swift` — understand how the monitor is started/stopped during recovery (Task 0)
- `Libraries/Sources/Core/FileSystemChecker.swift` — the protocol used for folder checks including `directoryExists` and `isReadable` (Task 0)
- `Libraries/Sources/Core/WatcherLogger.swift` — the logger protocol for verifying log output (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for verifying that the DirectoryMonitor is restarted after folder recovery (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock for simulating folder state changes (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift` — the mock for asserting on log output (Task 0)
- `plan.md` lines 79–96 — US-04 and US-05 acceptance criteria

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Write minimal implementation to make tests pass
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Note:** Folder polling uses exponential backoff (5s → 10s → 20s → 40s → 60s cap), injectable via the watcher's `clock` parameter (type: `any Clock<Duration>`). Tests should pass a custom clock that resolves `sleep(for:)` to zero delay, enabling instant state transitions without real-time waits. To verify the polling → monitoring transition behaviorally, tests should: (1) check `MockWatcherLogger` for the expected log messages, and (2) inject a file event via `MockDirectoryMonitor` after the transition and confirm the consumer receives a `VoiceMemoEvent`.

**Acceptance Criteria:**

- GIVEN `MockFileSystemChecker.existsResult` is `false` when `start()` is called, WHEN the watcher initializes, THEN it does not crash and `MockWatcherLogger.warnings` contains a message including the folder path
- GIVEN the watcher is in polling state for a missing folder, WHEN `MockFileSystemChecker` is changed to `existsResult = true` and `readableResult = true`, THEN `MockWatcherLogger.infos` contains a "monitoring started" message AND a new qualifying file event injected via the mock monitor is received by the consumer (proving the monitoring pipeline is operational)
- GIVEN the watcher is actively monitoring, WHEN `MockFileSystemChecker.existsResult` is changed to `false`, THEN `MockWatcherLogger.errors` contains a message and the watcher does not crash
- GIVEN the watcher is in polling state after folder deletion, WHEN `MockFileSystemChecker` is changed back to `existsResult = true` and `readableResult = true`, THEN monitoring resumes — verified by `MockWatcherLogger.infos` containing a "monitoring started" message and a subsequent file event being delivered to the consumer
- GIVEN `MockFileSystemChecker.existsResult` is `true` but `readableResult` is `false` when `start()` is called, WHEN the watcher initializes, THEN `MockWatcherLogger.errors` contains a message identifying the permission issue and no file events are emitted
- GIVEN the watcher has logged a permission error and is polling, WHEN `MockFileSystemChecker.readableResult` is changed to `true`, THEN `MockWatcherLogger.infos` contains a "monitoring started" message

**Do NOT:**
- Modify file qualification logic or the seen-set — that is Task 2 and Task 3/4a
- Test with the real iCloud Voice Memos directory — use mocks exclusively
- Add UI alerts or permission onboarding flows — out of scope per plan.md
- Implement multi-listener broadcast — that is Task 6
- Use real sleep/delay in tests — inject a custom clock that resolves sleep instantly

---

### Task 6: Implement Multi-Listener Broadcast

**Layer:** Core (Library)
**Blocked By:** Task 4a

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (add continuation registry for broadcast)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherBroadcastTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the current watcher implementation from Task 4a (or Task 5 if executed after)
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the event type being broadcast (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for injecting events (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock for simulating directory state (Task 0)
- `plan.md` lines 69–77 — US-03 acceptance criteria for listener consumption

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Write minimal implementation to make tests pass
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Note:** The broadcast uses a continuation registry protected by `@MainActor` isolation (per Key Decisions). When a consumer calls `events()`, a new `AsyncStream<VoiceMemoEvent>` is created with its own `Continuation`, which is added to the registry. The `onTermination` handler removes the continuation from the registry using `DispatchQueue.main.async` (the SE-0468 pattern). Each stream uses `.bufferingOldest(16)` buffering policy. Task 5 (folder handling) and Task 6 (broadcast) are independent — they can be executed in either order after Task 4a. **Baseline test setup:** all broadcast tests must configure `MockFileSystemChecker` with `existsResult = true` and `readableResult = true` so the watcher can start normally (important if Task 5's folder-availability checks have been implemented).

**Acceptance Criteria:**

- GIVEN `MockFileSystemChecker` configured with `existsResult = true` and `readableResult = true`, and two separate consumers each call `events()`, WHEN the watcher emits an event for a new file, THEN both consumers receive a `VoiceMemoEvent` with identical `fileURL` and `fileSize`
- GIVEN two consumers are listening and the watcher emits events for file A then file B, WHEN both consumers have received both events, THEN each consumer received A before B (ordering preserved per-consumer)
- GIVEN three consumers are listening and one consumer's stream is cancelled (the `AsyncStream` is dropped or the `for await` loop is broken), WHEN the watcher emits a new event, THEN the remaining two consumers still receive it without error
- GIVEN a consumer starts listening (calls `events()`) after the watcher has already emitted 2 events, WHEN the watcher emits a 3rd event, THEN the late consumer receives only the 3rd event (no replay of historical events)

**Do NOT:**
- Re-implement or modify file qualification logic — that is finalized in Task 2
- Re-implement startup catalog or seen-set logic — that is finalized in Task 3/4a
- Add event buffering or replay functionality — the stream is live-only per plan.md design
- Modify any files in `Utterd/`
