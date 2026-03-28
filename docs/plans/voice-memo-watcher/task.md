# Voice Memo File Watcher — Task Breakdown

**Plan**: [plan.md](plan.md)
**Date**: 2026-03-28
**Status**: In Progress

---

## Prerequisites

- **App Sandbox vs Voice Memos Access**: The current entitlements (`Utterd/Resources/Utterd.entitlements`) enable `com.apple.security.app-sandbox` with only network-client permission. A sandboxed app cannot access `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings` — this is Apple's group container and is not joinable by third-party apps. Before the watcher can be validated against the real directory, the sandbox must be disabled (appropriate for a non-App-Store single-user daemon) or user-granted folder access via security-scoped bookmarks must be implemented. **This is not a task in this plan** — it is a separate entitlements/permissions concern. All tasks here use temporary directories for testing and are valid regardless of the sandbox decision.

---

## Key Decisions

- **Module location: `Libraries/Sources/Core/`** — The watcher is domain infrastructure, not UI. Placing it in the local SPM package enables fast `swift test` without Xcode, aligns with the project's modularity goal (spec.md architecture decision), and keeps the `Utterd/` target focused on app-layer concerns. Alternative considered: `Utterd/Core/` — rejected because it couples the watcher to the app target and prevents independent testing.

- **Actor isolation: `@MainActor` for watcher state** — The watcher's state management (seen-set, continuation registry, lifecycle) is lightweight and benefits from the same isolation model the codebase already uses (`AppState`, `HomeModel` are all `@MainActor`). The actual filesystem monitoring (FSEvents) runs on its own dispatch queue regardless — `@MainActor` only governs the watcher's state, not the monitoring work. This avoids the `onTermination` actor-hop race condition: when an `AsyncStream` consumer cancels, the `onTermination` closure runs on an arbitrary executor — with `@MainActor`, cleanup uses `DispatchQueue.main.async` (the documented SE-0468 pattern). With a custom actor, it requires an unstructured `Task` hop that races with deinitialization. Alternative considered: custom `actor` — rejected due to the `onTermination` race.

- **Event delivery: `AsyncStream<VoiceMemoEvent>` with broadcast** — Swift's native `AsyncStream` fits the project's modern-Swift-first approach and avoids a Combine dependency. To support multiple concurrent consumers (AC-03.2), the watcher exposes a method that returns a new `AsyncStream` per caller, backed by a shared continuation registry. Each stream uses `.bufferingOldest(16)` buffering policy — prevents unbounded memory growth from slow consumers while preserving event ordering. Alternative considered: `PassthroughSubject` from Combine — rejected because the rest of the codebase uses async/await, not Combine.

- **Filesystem monitoring: FSEvents C API (`FSEventStreamCreate` from CoreServices) with `kFSEventStreamCreateFlagFileEvents`** — `DispatchSource.makeFileSystemObjectSource` uses kqueue, which fires on directory entry changes (add/remove/rename) but NOT on in-place file content growth. iCloud sync may write files in-place rather than using atomic replace, so kqueue would miss mid-sync files growing past the 1024-byte threshold (violating AC-01.3 and AC-02.3). The FSEvents C API with `kFSEventStreamCreateFlagFileEvents` reports per-file content modifications. `import CoreServices` works directly in SPM packages — no additional dependency needed. Alternative considered: `DispatchSource` — rejected because it cannot detect in-place file growth.

- **DirectoryMonitor stream delivery: `start() throws -> AsyncStream<Set<URL>>`** — The monitor's `start()` method returns a fresh event stream carrying the set of changed file URLs per notification, matching FSEvents' native output. Returning the stream from `start()` (rather than exposing it as a property) ensures each start/stop cycle gets a new stream — critical for Task 5's recovery flow where the monitor is restarted after folder reappearance. This allows the watcher to check only the changed files rather than rescanning the entire directory. Alternative considered: `events` as a property — rejected because a property returns the same stream instance, which cannot be reused after `stop()` finishes it.

- **Testability via protocols** — Three protocols abstract external dependencies: `DirectoryMonitor` (FSEvents), `FileSystemChecker` (FileManager), `WatcherLogger` (os.Logger). Tests inject mock implementations for fast, deterministic execution. This follows the project's established DI pattern. Mock types are `@unchecked Sendable` classes — their use is confined to `@MainActor` test functions where actor isolation is guaranteed by the test annotation, so the `@unchecked` is safe. Alternative considered: integration-only testing with temp directories — rejected as slow and non-deterministic.

- **Seen-set data structure: `[URL: Int64?]` with permanent emission tracking** — Maps each file URL to its last-known size at evaluation time. `nil` means "cataloged but not yet qualified/emitted." This distinguishes "seen but unqualified" from "seen and emitted," which is critical for the mid-sync scenario (AC-02.3). Once a file qualifies and an event is emitted, the size is recorded and the entry is treated as permanently emitted — subsequent size changes for that path do NOT trigger re-emission (AC-01.5 requires at most one event per file path after it first meets the fully-synced criteria). To implement: once a file qualifies, store a sentinel value (e.g., `Int64.max`) or use a separate `emittedPaths: Set<URL>` — check this set first, before any re-evaluation. Alternative considered: `Set<URL>` — rejected because it cannot detect size changes for the mid-sync scenario.

- **Polling for missing/permission-denied folder: exponential backoff** — When the sync folder is missing or unreadable, the watcher polls starting at 5 seconds, doubling each cycle up to 60 seconds (5s → 10s → 20s → 40s → 60s → 60s…). This stays within the plan's 5–60 second range. The backoff schedule is injectable via a `Clock` parameter (`any Clock<Duration>`, defaulting to `ContinuousClock()`). Tests pass a custom clock that resolves sleep to zero delay. Alternative considered: fixed 10-second interval — rejected as wasteful for long-missing folders.

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
| AC-01.3: File transitions from placeholder to fully-synced → exactly one event | Task 4 |
| AC-01.4: Event includes file name and size in log | Task 4 |
| AC-01.5: No duplicate events for same path | Task 3 |
| AC-01.6: 5 files in 1 second → 5 events | Task 4 |
| AC-01.7: Non-.m4a files → no event | Task 2 |
| AC-01.8: Folder deleted/inaccessible → log error, retry 5–60s | Task 5 |
| AC-01.9: Folder reappears → monitoring resumes | Task 5 |
| AC-02.1: Existing files at startup → zero events | Task 3 |
| AC-02.2: New file after startup → one event | Task 3 |
| AC-02.3: Mid-sync file at startup, later grows → one event | Task 4 |
| AC-03.1: Listener receives file URL and size | Task 2 (event type), Task 3 (emission) |
| AC-03.2: Multiple listeners each receive event | Task 6 |
| AC-04.1: Missing folder at start → log warning, poll 5–60s | Task 5 |
| AC-04.2: Missing folder appears → monitoring begins | Task 5 |
| AC-05.1: No read permission → log error, no events | Task 5 |
| AC-05.2: Permission later granted → monitoring starts | Task 5 |
| Edge: .icloud placeholder then real file | Task 4 |
| Edge: File stays ≤ 1024 bytes | Task 2 |
| Edge: Exactly 1024 bytes → no event | Task 2 |
| Edge: Rapid burst of files | Task 4 |
| Edge: Non-.m4a files ignored | Task 2 |
| Edge: App restart with mid-sync files | Task 4 |
| Edge: Multiple FS events for same path coalesced | Task 3 |
| Edge: File deletion from watched folder | Task 4 |
| Edge: Sync folder disappears mid-operation | Task 5 |
| Edge: No read permission | Task 5 |
| Success: exactly-once emission | Task 3, Task 4 |
| Success: zero events for pre-existing files | Task 3 |
| Success: zero events for placeholders/small files | Task 2 |
| SC-4: Memory footprint ≤ 10% growth after 100 events | **Deferred — out of scope for this plan.** Requires profiling tooling outside unit tests. The seen-set grows linearly (~80 bytes/entry); at 10 memos/day, annual growth is ~285 KB (negligible). The set resets on restart. No task in this plan verifies this criterion. |
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
- `Libraries/Tests/CoreTests/Mocks/ImmediateClock.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/Core.swift` — understand the existing module structure and public API surface
- `Libraries/Package.swift` — confirm target layout; Swift PM recursively includes `Tests/CoreTests/**/*.swift` so the `Mocks/` subdirectory will be picked up automatically
- `spec.md` lines 53–69 — understand pipeline architecture and where the watcher fits

**Steps:**

1. [ ] Define `VoiceMemoEvent` struct in `VoiceMemoEvent.swift`: mark it `public`, `Sendable`, `Equatable`; add two stored properties — `fileURL: URL` and `fileSize: Int64` — and a `public init`
2. [ ] Define `DirectoryMonitor` protocol in `DirectoryMonitor.swift`: `start() throws -> AsyncStream<Set<URL>>` to begin monitoring and return a fresh event stream (returning the stream from `start()` rather than exposing it as a property ensures each start/stop cycle gets a new stream — this is required for Task 5's recovery flow where the monitor is restarted), `stop()` to end monitoring and finish the current stream; mark the protocol `Sendable`
3. [ ] Define `FileSystemChecker` protocol in `FileSystemChecker.swift`: four methods — `directoryExists(at: URL) -> Bool`, `isReadable(at: URL) -> Bool`, `contentsOfDirectory(at: URL) -> [URL]`, `fileSize(at: URL) -> Int64?`; mark the protocol `Sendable`
4. [ ] Define `WatcherLogger` protocol in `WatcherLogger.swift`: three methods — `info(_: String)`, `warning(_: String)`, `error(_: String)`; mark the protocol `Sendable`
5. [ ] Define `VoiceMemoWatcher` class in `VoiceMemoWatcher.swift`: annotate `@MainActor public final class`; add stored properties for `directoryURL: URL`, `monitor: any DirectoryMonitor`, `fileSystem: any FileSystemChecker`, `logger: any WatcherLogger`, `clock: any Clock<Duration>`; implement `public init` with `clock` defaulting to `ContinuousClock()`; add stub methods `start() async`, `stop()`, and `events() -> AsyncStream<VoiceMemoEvent>` (return an immediately-finishing stream for now)
6. [ ] Create `MockDirectoryMonitor` in `Mocks/MockDirectoryMonitor.swift`: each call to `start()` creates a fresh `AsyncStream<Set<URL>>` and continuation pair (replacing any previous stream) — this supports Task 5's recovery tests where the monitor is stopped and restarted; expose `emit(_ changedURLs: Set<URL>)` to yield into the current stream, `failOnStart: Bool` flag, and `completeStream()` to finish the current stream
7. [ ] Create `MockFileSystemChecker` in `Mocks/MockFileSystemChecker.swift`: mutable properties `existsResult: Bool = true`, `readableResult: Bool = true`, `directoryContents: [URL] = []`, `fileSizes: [URL: Int64] = [:]`; add a `directoryExistsCallCount: Int = 0` counter that increments on each `directoryExists(at:)` call, and an optional callback `onDirectoryExistsCheck: ((Int) -> Void)?` that fires with the call count — this enables Task 5 tests to synchronize mock state changes with the polling loop; implement protocol methods returning the configured values
8. [ ] Create `MockWatcherLogger` in `Mocks/MockWatcherLogger.swift`: three mutable arrays `infos: [String]`, `warnings: [String]`, `errors: [String]`; each protocol method appends to its array
9. [ ] Create `ImmediateClock` in `Mocks/ImmediateClock.swift`: a `Clock` implementation where `Duration == Swift.Duration` that calls `await Task.yield()` in `sleep(for:)` and then returns immediately — this ensures cooperative scheduling while eliminating real-time waits, preventing the polling loop from spinning without yielding the `@MainActor`; use `ContinuousClock.Instant` as the `Instant` type and delegate `now` to `ContinuousClock()`
10. [ ] Verify all types compile: `cd Libraries && swift build`

**Acceptance Criteria:**

- GIVEN the `VoiceMemoEvent` struct, WHEN inspected, THEN it is `public`, `Sendable`, `Equatable`, and contains `fileURL: URL` and `fileSize: Int64`
- GIVEN the `DirectoryMonitor` protocol, WHEN read by a developer, THEN it defines `start() throws -> AsyncStream<Set<URL>>` (returns a fresh stream per call) and `stop()`
- GIVEN the `FileSystemChecker` protocol, WHEN read by a developer, THEN it defines `directoryExists(at:)`, `isReadable(at:)`, `contentsOfDirectory(at:)`, and `fileSize(at:)`
- GIVEN the `WatcherLogger` protocol, WHEN read, THEN it defines `info(_:)`, `warning(_:)`, and `error(_:)` methods accepting `String`
- GIVEN the `VoiceMemoWatcher` interface, WHEN a consumer reads it, THEN they know how to initialize it (directory URL, `DirectoryMonitor`, `FileSystemChecker`, `WatcherLogger`, `clock: any Clock<Duration>`), start/stop it, and obtain an `AsyncStream<VoiceMemoEvent>` via `events()`
- GIVEN all mock types, WHEN used in tests, THEN they produce configurable, deterministic behavior matching the protocol contracts
- GIVEN `MockFileSystemChecker`, WHEN `directoryExists(at:)` is called 3 times, THEN `directoryExistsCallCount` is `3` and `onDirectoryExistsCheck` was called with counts 1, 2, 3
- GIVEN `ImmediateClock`, WHEN `sleep(for: .seconds(60))` is called, THEN the call returns immediately without real-time delay (it yields the current task for cooperative scheduling but does not wait)
- GIVEN all contract and mock files, WHEN `cd Libraries && swift build` is run, THEN compilation succeeds with no errors

**Do NOT:**
- Implement any watcher logic (file filtering, seen-set tracking, polling) — only define the shapes
- Implement the production `FSEventsDirectoryMonitor` — that is Task 1
- Create the `VoiceMemoQualifier` — that is Task 2

---

### Task 1: Implement FSEvents DirectoryMonitor

**Layer:** Core (Library)
**Blocked By:** Task 0


**Relevant Files:**
- `Libraries/Sources/Core/FSEventsDirectoryMonitor.swift` ← create
- `Libraries/Tests/CoreTests/FSEventsDirectoryMonitorTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/DirectoryMonitor.swift` — the protocol this implementation conforms to; `start()` returns a fresh `AsyncStream<Set<URL>>` of changed file paths per call (Task 0)
- `Libraries/Tests/CoreTests/CoreTests.swift` — understand existing test patterns (@Suite, @Test, #expect)
- `spec.md` lines 53–69 — pipeline architecture context

**Steps:**

1. [ ] Write failing tests: (a) test that creating a file in a temporary directory causes the stream returned by `start()` to emit a `Set<URL>` containing that file's URL within 10 seconds; (b) test that calling `stop()` causes the stream to finish; (c) test that starting with a nonexistent directory throws; (d) test that after stop(), calling `start()` again returns a new functional stream (restart support for Task 5)
2. [ ] Run tests to verify they fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Implement `FSEventsDirectoryMonitor` as a `final class` conforming to `DirectoryMonitor` and `@unchecked Sendable` (thread safety is guaranteed by the dedicated dispatch queue serializing all callback access, and `Continuation.yield` is thread-safe): import `CoreServices`; store the directory path, an `AsyncStream<Set<URL>>` with its continuation, and a dedicated `DispatchQueue` for the FSEvents stream
4. [ ] Implement `start()`: use `Unmanaged.passRetained(self)` to create a context pointer (this prevents premature deallocation while the FSEventStream is running); create an `FSEventStream` using `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot`, a latency of 0.3 seconds, and a C callback; `kFSEventStreamCreateFlagWatchRoot` is required — without it, `kFSEventStreamEventFlagRootChanged` is never delivered and Task 5's mid-operation folder-disappearance detection is silently inoperative; schedule the stream on the dedicated `DispatchQueue` and call `FSEventStreamStart`; in the C callback, check for `kFSEventStreamEventFlagRootChanged` — if present, finish the continuation (this signals the watcher that the directory was deleted/unmounted); otherwise convert reported paths to `Set<URL>` and yield into the continuation; each call to `start()` must create a fresh `AsyncStream` and continuation pair (replacing any previous stream) to support restart after stop — this is required for Task 5's recovery flow
5. [ ] Implement `stop()` with a boolean guard (`private var isRunning = false`): if not running, return immediately (prevents double-release); otherwise set `isRunning = false`, call `FSEventStreamStop`, `FSEventStreamInvalidate`, finish the continuation, and release the retained self via `Unmanaged.fromOpaque(ptr).release()`; add a `deinit` that calls `stop()` as a safety net — the guard ensures no double-release if `stop()` was already called
6. [ ] Run tests to verify they pass (confirm GREEN state): `cd Libraries && swift test`

**Note:** This task creates **integration tests** that interact with the real filesystem via the FSEvents C API. These tests are inherently slower and more timing-sensitive than the mock-based unit tests in other tasks. Use Swift Testing's `@Test(.timeLimit(.minutes(1)))` annotation for timing-sensitive tests, with a 10-second polling loop inside the test for event delivery. The class must be `@unchecked Sendable` because the dispatch queue provides thread safety — document this in a comment. Use `Unmanaged.passRetained(self)` in `start()` and balance with `release()` in `stop()` to prevent use-after-free if the monitor is deallocated while the FSEventStream is active.

**Acceptance Criteria:**

- GIVEN an `FSEventsDirectoryMonitor` initialized with a valid temporary directory path, WHEN `start()` is called and a new file is created in that directory, THEN the returned async stream emits a `Set<URL>` containing the new file's URL within 10 seconds
- GIVEN an `FSEventsDirectoryMonitor` that is running, WHEN `stop()` is called, THEN the async stream returned by `start()` completes (finishes) and no further events are delivered
- GIVEN an `FSEventsDirectoryMonitor`, WHEN `start()` is called with a path to a directory that does not exist, THEN it throws an error
- GIVEN an `FSEventsDirectoryMonitor` that was started and stopped, WHEN `start()` is called again, THEN it returns a new, functional async stream (supporting restart for Task 5's recovery flow)

**Do NOT:**
- Implement file filtering (.m4a, size checks, placeholder detection) — the monitor reports raw directory changes; filtering is the watcher's job (Tasks 2–4)
- Add polling/retry logic for missing folders — that is the watcher's responsibility (Task 5)
- Test with the real iCloud Voice Memos directory — use temporary directories only
- Use mocks or synthetic events — this is the one task where real filesystem I/O is intentional
- Use `DispatchSource` — it cannot detect in-place file growth; use `FSEventStreamCreate` from CoreServices

---

### Task 2: Implement File Qualification Logic

**Layer:** Core (Library)
**Blocked By:** Task 0

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoQualifier.swift` ← create
- `Libraries/Tests/CoreTests/VoiceMemoQualifierTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the event type returned when a file qualifies (Task 0)
- `plan.md` lines 47–54, 99–107 — acceptance criteria and edge cases for file qualification rules

**Steps:**

1. [ ] Write failing tests for all nine acceptance criteria below: construct file URLs with specific extensions and filenames, pass them with specific sizes to `qualifies(url:fileSize:)`, and assert the return value is either a `VoiceMemoEvent` or `nil`
2. [ ] Run tests to verify they fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Implement `VoiceMemoQualifier` as a `struct` with a single static method `qualifies(url: URL, fileSize: Int64) -> VoiceMemoEvent?`: check that the file extension is `m4a`, that the filename does not start with `.` (iCloud placeholder convention: `.originalname.icloud`), that the path extension is not `icloud`, and that the size exceeds 1024 bytes; if all checks pass, return a `VoiceMemoEvent`; otherwise return `nil`
4. [ ] Run tests to verify they pass (confirm GREEN state): `cd Libraries && swift test`

**Acceptance Criteria:**

- GIVEN a file URL with extension `.m4a` and file size 2048 bytes whose filename does not start with a dot, WHEN `qualifies(url:fileSize:)` is called, THEN it returns a `VoiceMemoEvent` with the file's URL and size
- GIVEN a file URL with extension `.m4a` and file size exactly 1024 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil` (threshold is strictly greater than 1024)
- GIVEN a file URL with extension `.m4a` and file size 512 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.m4a` and file size 0 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.txt` and file size 2048 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.jpg` and file size 2048 bytes, WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with path component `.memo.m4a.icloud` (leading dot, `.icloud` extension — iCloud placeholder convention), WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with path component `.voice_memo.m4a.icloud` (another iCloud placeholder variant), WHEN `qualifies(url:fileSize:)` is called, THEN it returns `nil`
- GIVEN a file URL with extension `.m4a` and file size 1025 bytes whose filename does not start with a dot, WHEN `qualifies(url:fileSize:)` is called, THEN it returns a `VoiceMemoEvent` (just above threshold)

**Do NOT:**
- Access the filesystem to read file attributes — accept URL and file size as parameters so the logic is purely functional and testable without disk I/O
- Track seen files or deduplication — that is the watcher's job (Task 3)
- Add logging — that is Task 4's responsibility

---

### Task 3: Implement Core Watcher Logic (Startup Catalog and Basic Event Emission)

**Layer:** Core (Library)
**Blocked By:** Task 0, Task 2

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (add implementation to the interface from Task 0)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherTests.swift` ← create
- `Libraries/Tests/CoreTests/Helpers/WatcherTestHelper.swift` ← create (shared helper for building a VoiceMemoWatcher with mock dependencies — reused by Tasks 4, 5, 6)

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the public interface defined in Task 0; this is the file being modified
- `Libraries/Sources/Core/DirectoryMonitor.swift` — the protocol; `start()` returns `AsyncStream<Set<URL>>` of changed paths (Task 0)
- `Libraries/Sources/Core/FileSystemChecker.swift` — the protocol for filesystem queries including `contentsOfDirectory` and `fileSize` (Task 0)
- `Libraries/Sources/Core/VoiceMemoQualifier.swift` — the qualification logic used to filter files (Task 2)
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the event type emitted (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for injecting synthetic FS events (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock for configuring directory contents and file sizes (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift` — the mock for capturing log output (Task 0)

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below: create a helper that builds a `VoiceMemoWatcher` with mock dependencies; test startup catalog suppression, new file emission, deduplication, non-qualifying file rejection, and clean shutdown
2. [ ] Run tests to verify they fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Implement `start()`: initialize an `emittedPaths: Set<URL>` (tracks permanently emitted files — once a file is in this set, it never triggers another event) and a seen-set `[URL: Int64?]`; call `fileSystem.contentsOfDirectory(at: directoryURL)` to enumerate existing files; for each file, call `fileSystem.fileSize(at:)` and populate the seen-set — if the file qualifies via `VoiceMemoQualifier`, add it to `emittedPaths` and store its size in the seen-set (marking it as "already emitted, never re-emit"); if it doesn't qualify, store `nil` in the seen-set (marking it as "seen but not yet emitted, pending growth"); then call `let eventStream = try monitor.start()` and begin consuming `eventStream`
4. [ ] Implement change handling: for each `Set<URL>` from the monitor's stream, iterate the URLs; for each URL, call `fileSystem.fileSize(at:)` — if it returns `nil` (file was deleted or cannot be stat'd), skip the URL silently; otherwise run `VoiceMemoQualifier.qualifies(url:fileSize:)` — if it qualifies AND the URL is not already in the `emittedPaths` set, emit a `VoiceMemoEvent` to the continuation, add the URL to `emittedPaths`, and update the seen-set; if it doesn't qualify, add it to the seen-set with `nil` size so it can be re-evaluated later when the file grows (this `nil` storage is critical for Task 4's mid-sync growth detection)
5. [ ] Implement `stop()`: call `monitor.stop()` and finish the event stream continuation
6. [ ] Implement `events()`: create a new `AsyncStream<VoiceMemoEvent>` with `.bufferingOldest(16)` and store its continuation; for this task, support only a single consumer (broadcast comes in Task 6)
7. [ ] Run tests to verify they pass (confirm GREEN state): `cd Libraries && swift test`

**Acceptance Criteria:**

- GIVEN `MockFileSystemChecker` configured with 3 qualifying `.m4a` files (each > 1024 bytes) in `directoryContents` and `fileSizes`, WHEN `start()` is called and a consumer iterates the event stream, and then the mock monitor emits a change for a NEW 4th qualifying file (also configured in `MockFileSystemChecker`), THEN exactly one event is emitted for the 4th file — the 3 pre-existing files produce zero events
- GIVEN the watcher has started and cataloged existing files, WHEN the mock monitor emits a change containing a URL for a new qualifying `.m4a` file (configured in `MockFileSystemChecker` with size 2048), THEN exactly one `VoiceMemoEvent` is emitted with that file's URL and `fileSize: 2048`
- GIVEN the watcher has already emitted an event for a file URL, WHEN the mock monitor emits another change containing that same URL and `MockFileSystemChecker` still reports the same size, THEN no additional event is emitted (deduplication)
- GIVEN the watcher is running, WHEN the mock monitor emits a change containing a URL with extension `.txt` (configured in `MockFileSystemChecker`), THEN no event is emitted (qualifier rejects it)
- GIVEN the watcher is running, WHEN the mock monitor emits a change containing a URL for a `.m4a` file and `MockFileSystemChecker.fileSize` returns 512 for that URL, THEN no event is emitted (qualifier rejects it)
- GIVEN the watcher received a change for a `.m4a` file at 512 bytes (no event emitted), WHEN `MockFileSystemChecker.fileSizes` is updated to report 2048 bytes for that URL and the mock monitor emits another change containing that URL, THEN exactly one `VoiceMemoEvent` is emitted with `fileSize: 2048` — this verifies the seen-set stores unqualified files with `nil` size for re-evaluation, which Task 4 depends on
- GIVEN a consumer is iterating the watcher's event stream, WHEN `stop()` is called on the watcher, THEN the event stream completes and the `for await` loop exits cleanly

**Do NOT:**
- Implement folder-missing or permission-error recovery — that is Task 5
- Implement the broadcast/multi-listener pattern — that is Task 6; this task tests with a single consumer
- Implement burst handling (batch Set processing), deletion handling (fileSize returns nil during change processing), or logging — that is Task 4
- Use real filesystem monitoring — use `MockDirectoryMonitor` to inject synthetic change events and `MockFileSystemChecker` for all filesystem queries
- Add UI integration or modify any files in `Utterd/`

---

### Task 4: Implement Advanced Change-Handler Behaviors

**Layer:** Core (Library)
**Blocked By:** Task 3

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (extend the implementation from Task 3)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherAdvancedTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the current watcher implementation from Task 3
- `Libraries/Sources/Core/VoiceMemoQualifier.swift` — the qualification logic (Task 2)
- `Libraries/Sources/Core/WatcherLogger.swift` — the logger protocol (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for injecting events (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock for configuring file sizes (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift` — the mock for asserting on log output (Task 0)
- `Libraries/Tests/CoreTests/Helpers/WatcherTestHelper.swift` — shared helper for building a watcher with mock dependencies (Task 3)
- `plan.md` lines 42–54, 99–110 — acceptance criteria and edge cases

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below: test mid-sync growth detection, burst emission, logging on event, deletion resilience, and placeholder-to-real-file transition
2. [ ] Run tests to verify they fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Implement mid-sync growth detection: in the change handler, when a URL already exists in the seen-set with `nil` size (unqualified), re-evaluate it via `VoiceMemoQualifier` with the new file size; if it now qualifies AND the URL is not in `emittedPaths`, emit the event, add to `emittedPaths`, and update the seen-set
4. [ ] Add logging on event emission: after emitting each `VoiceMemoEvent`, call `logger.info()` with a message containing the file's `lastPathComponent` and the file size in bytes
5. [ ] Add deletion resilience: when `fileSystem.fileSize(at:)` returns `nil` for a changed URL (file was deleted), skip the URL without crashing or logging an error — silently ignore deletions
6. [ ] Run tests to verify they pass (confirm GREEN state): `cd Libraries && swift test`

**Note:** The mid-sync growth scenario relies on the seen-set storing `nil` for unqualified files (established in Task 3's startup catalog). When the monitor reports a change for that URL and the file size has grown past 1024 bytes, the re-evaluation triggers event emission. The burst scenario is tested by emitting multiple distinct URLs in separate notifications and verifying one event per file.

**Acceptance Criteria:**

- GIVEN `MockFileSystemChecker` is configured with `memo.m4a` at 512 bytes in `directoryContents` at startup (cataloged with `nil` size), WHEN the watcher starts, then `MockFileSystemChecker.fileSizes` is updated to report `memo.m4a` at 2048 bytes, and the mock monitor emits a change containing `memo.m4a`'s URL, THEN exactly one `VoiceMemoEvent` is emitted with `fileSize: 2048`
- GIVEN the watcher has emitted an event for `memo.m4a` at 2048 bytes (recorded in seen-set), WHEN `MockFileSystemChecker` still reports 2048 and the mock monitor emits another change containing that URL, THEN no additional event is emitted
- GIVEN the watcher is running, WHEN the mock monitor emits 5 separate change notifications each containing the URL of a distinct new qualifying `.m4a` file (all configured in `MockFileSystemChecker` with sizes > 1024), THEN exactly 5 events are emitted, one per file, in the order the notifications were delivered
- GIVEN the watcher is running, WHEN the mock monitor emits a SINGLE change notification containing a `Set` of 3 distinct qualifying `.m4a` URLs (all configured in `MockFileSystemChecker`), THEN 3 events are emitted, one per file
- GIVEN the watcher emits an event for a file, WHEN `MockWatcherLogger.infos` is inspected, THEN it contains a message including the file name and the file size in bytes
- GIVEN a previously cataloged file URL, WHEN `MockFileSystemChecker.fileSize` is updated to return `nil` for that URL (simulating deletion) and the mock monitor emits a change containing that URL, THEN the watcher does not crash and no error event or error log is emitted
- GIVEN the watcher's seen-set contains `.memo.m4a.icloud` (cataloged at startup), WHEN `MockFileSystemChecker` is updated so `memo.m4a` appears with size 2048, and the mock monitor emits a change containing `memo.m4a`'s URL, THEN exactly one event is emitted for `memo.m4a` — confirming the placeholder-to-real-file transition is treated as a new qualifying file

**Do NOT:**
- Modify startup catalog logic — that is finalized in Task 3
- Implement folder-missing or permission-error recovery — that is Task 5
- Implement multi-listener broadcast — that is Task 6
- Modify `VoiceMemoQualifier` — the filtering rules are fixed in Task 2
- Add UI integration or modify any files in `Utterd/`

---

### Task 5: Implement Folder Unavailability Handling (Missing, Permissions, Recovery)

**Layer:** Core (Library)
**Blocked By:** Task 4

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (add folder availability checks and polling)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherFolderTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the current watcher implementation from Task 4
- `Libraries/Sources/Core/DirectoryMonitor.swift` — `start()` returns a fresh stream per call, enabling restart after recovery (Task 0)
- `Libraries/Sources/Core/FileSystemChecker.swift` — the protocol used for `directoryExists` and `isReadable` checks (Task 0)
- `Libraries/Sources/Core/WatcherLogger.swift` — the logger protocol for verifying log output (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for verifying that the monitor is restarted after recovery; `completeStream()` simulates the FSEvents stream ending (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock with `directoryExistsCallCount` and `onDirectoryExistsCheck` callback for synchronizing mock state changes with the polling loop (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockWatcherLogger.swift` — the mock for asserting on log output (Task 0)
- `Libraries/Tests/CoreTests/Mocks/ImmediateClock.swift` — the zero-delay clock for instant polling loop execution (Task 0)
- `Libraries/Tests/CoreTests/Helpers/WatcherTestHelper.swift` — shared helper for building a watcher with mock dependencies (Task 3)
- `plan.md` lines 79–96 — US-04 and US-05 acceptance criteria

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below: use `ImmediateClock` (from Task 0) so polling loops execute instantly; use `MockFileSystemChecker.onDirectoryExistsCheck` callback to synchronize mock state changes with the polling loop (e.g., set `existsResult = true` after the 2nd call to simulate the folder appearing)
2. [ ] Run tests to verify they fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Add a pre-check at the beginning of `start()`: before enumerating files or starting the monitor, call `fileSystem.directoryExists(at: directoryURL)` and `fileSystem.isReadable(at: directoryURL)`; if the directory is missing, log a warning and enter polling state; if it exists but is not readable, log a permission error and enter polling state
4. [ ] Implement the polling loop: use `clock.sleep(for:)` with exponential backoff (start at 5 seconds, double each iteration, cap at 60 seconds); on each tick, re-check `directoryExists` and `isReadable`; when both return `true`, log "monitoring started", proceed to enumerate existing files, call `let eventStream = try monitor.start()` to get a fresh stream, and begin processing events (reusing the startup logic from Task 3)
5. [ ] Handle mid-operation folder disappearance: when the monitor's event stream finishes (the `for await` loop exits naturally — in production, FSEvents finishes the stream when it detects `kFSEventStreamEventFlagRootChanged` via `kFSEventStreamCreateFlagWatchRoot`; in tests, `mockMonitor.completeStream()` simulates this), call `monitor.stop()`, then check `fileSystem.directoryExists(at:)` — if the directory is gone, log an error and re-enter the polling loop with reset backoff; if the directory still exists, attempt to restart by calling `monitor.start()` again to get a fresh stream
6. [ ] Run tests to verify they pass (confirm GREEN state): `cd Libraries && swift test`

**Note:** Folder polling uses exponential backoff (5s → 10s → 20s → 40s → 60s cap), injectable via the watcher's `clock` parameter. Tests use `ImmediateClock` (Task 0) for zero-delay polling. To synchronize mock state changes with the polling loop, use `MockFileSystemChecker.onDirectoryExistsCheck` — this callback fires on each `directoryExists(at:)` call with the cumulative call count, letting the test set `existsResult = true` at a specific iteration. Mid-operation folder disappearance is simulated by calling `mockMonitor.completeStream()` (mimicking FSEvents finishing the stream on `kFSEventStreamEventFlagRootChanged`) and setting `existsResult = false`.

**Acceptance Criteria:**

- GIVEN `MockFileSystemChecker.existsResult` is `false` when `start()` is called, WHEN the watcher initializes, THEN it does not crash and `MockWatcherLogger.warnings` contains a message including the folder path
- GIVEN the watcher is in polling state for a missing folder and `MockFileSystemChecker.onDirectoryExistsCheck` is configured to set `existsResult = true` and `readableResult = true` after the 2nd check, WHEN the polling loop reaches the 3rd check, THEN `MockWatcherLogger.infos` contains a "monitoring started" message AND a new qualifying file event injected via the mock monitor is received by the consumer (proving the monitoring pipeline is operational)
- GIVEN the watcher is actively monitoring, WHEN `mockMonitor.completeStream()` is called (simulating the FSEvents stream ending due to directory removal) AND `MockFileSystemChecker.existsResult` is `false`, THEN `MockWatcherLogger.errors` contains a message and the watcher enters the polling state without crashing
- GIVEN the watcher is in polling state after folder deletion and `MockFileSystemChecker.onDirectoryExistsCheck` is configured to set `existsResult = true` and `readableResult = true` after the 2nd check, WHEN the polling loop reaches the 3rd check, THEN monitoring resumes — verified by a "monitoring started" log message and a subsequent file event being delivered to the consumer
- GIVEN `MockFileSystemChecker.existsResult` is `true` but `readableResult` is `false` when `start()` is called, WHEN the watcher initializes, THEN `MockWatcherLogger.errors` contains a message identifying the permission issue and no file events are emitted
- GIVEN the watcher has logged a permission error and `MockFileSystemChecker.onDirectoryExistsCheck` is configured to set `readableResult = true` after the 2nd check, WHEN the polling loop reaches the 3rd check, THEN `MockWatcherLogger.infos` contains a "monitoring started" message

**Do NOT:**
- Modify file qualification logic or the seen-set — that is Task 2 and Task 3/4
- Test with the real iCloud Voice Memos directory — use mocks exclusively
- Add UI alerts or permission onboarding flows — out of scope per plan.md
- Implement multi-listener broadcast — that is Task 6
- Use real sleep/delay in tests — use `ImmediateClock` from Task 0

---

### Task 6: Implement Multi-Listener Broadcast

**Layer:** Core (Library)
**Blocked By:** Task 5

**Relevant Files:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` ← modify (add continuation registry for broadcast)
- `Libraries/Tests/CoreTests/VoiceMemoWatcherBroadcastTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/VoiceMemoWatcher.swift` — the current watcher implementation from Task 5
- `Libraries/Sources/Core/VoiceMemoEvent.swift` — the event type being broadcast (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockDirectoryMonitor.swift` — the mock for injecting events (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the mock for simulating directory state (Task 0)
- `Libraries/Tests/CoreTests/Helpers/WatcherTestHelper.swift` — shared helper for building a watcher with mock dependencies (Task 3)
- `plan.md` lines 69–77 — US-03 acceptance criteria for listener consumption

**Steps:**

1. [ ] Write failing tests based on the acceptance criteria below: configure `MockFileSystemChecker` with `existsResult = true` and `readableResult = true` so the watcher can start normally; test two-listener delivery, event ordering, graceful stream cancellation, and late-joiner behavior
2. [ ] Run tests to verify they fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Refactor `events()` to use a continuation registry: replace the single-continuation approach from Task 3 with an array of `AsyncStream<VoiceMemoEvent>.Continuation`; each call to `events()` creates a new `AsyncStream` with `.bufferingOldest(16)`, stores its continuation in the registry, and sets an `onTermination` handler that removes the continuation from the registry using `DispatchQueue.main.async` (SE-0468 pattern for `@MainActor` safety)
4. [ ] Refactor event emission to broadcast: wherever the watcher yields a `VoiceMemoEvent` (in the change handler from Tasks 3–5), iterate all continuations in the registry and yield the event to each one
5. [ ] Run tests to verify they pass (confirm GREEN state): `cd Libraries && swift test`

**Note:** Task 6 runs after Task 5 to avoid merge conflicts (both modify `VoiceMemoWatcher.swift`). All broadcast tests must configure `MockFileSystemChecker` with `existsResult = true` and `readableResult = true` so the watcher can start normally (Task 5's folder-availability pre-checks are in place). After cancelling a consumer's stream, call `await Task.yield()` before emitting the next event — this allows the `onTermination` `DispatchQueue.main.async` callback to execute and remove the cancelled continuation from the registry.

**Acceptance Criteria:**

- GIVEN `MockFileSystemChecker` configured with `existsResult = true` and `readableResult = true`, and two separate consumers each call `events()`, WHEN the watcher emits an event for a new file, THEN both consumers receive a `VoiceMemoEvent` with identical `fileURL` and `fileSize`
- GIVEN two consumers are listening and the watcher emits events for file A then file B, WHEN both consumers have received both events, THEN each consumer received A before B (ordering preserved per-consumer)
- GIVEN three consumers are listening and one consumer's stream is cancelled (the `for await` loop is broken), WHEN `await Task.yield()` is called to allow the `onTermination` `DispatchQueue.main.async` callback to execute, and THEN the watcher emits a new event, THEN the remaining two consumers still receive it without error
- GIVEN a consumer starts listening (calls `events()`) after the watcher has already emitted 2 events, WHEN the watcher emits a 3rd event, THEN the late consumer receives only the 3rd event (no replay of historical events)

**Do NOT:**
- Re-implement or modify file qualification logic — that is finalized in Task 2
- Re-implement startup catalog or seen-set logic — that is finalized in Task 3/4
- Add event buffering or replay functionality — the stream is live-only per plan.md design
- Modify any files in `Utterd/`
