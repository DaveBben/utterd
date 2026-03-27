# Filesystem Watcher — Task Breakdown

**Plan**: [plan.md](plan.md)
**Date**: 2026-03-26
**Status**: In Progress

---

## Layers

| Layer | Covers | Key directories/files |
|-------|--------|-----------------------|
| Core Library | Filesystem watcher implementation and all tests | `Libraries/Sources/Core/`, `Libraries/Tests/CoreTests/` |

This is a single-layer change. All code lives in the local SPM package (`Libraries/`). No app-level code, UI, or multi-layer parallelism is involved. Tasks execute sequentially within one agent session.

**Build & test command**: `cd Libraries && swift build && swift test`

---

## Open Questions

None — all decisions resolved during planning.

---

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Use FSEvents via CoreServices framework | FSEvents is the macOS API for efficient directory monitoring. It coalesces rapid file system events at the OS level, supports latency-based batching, and is the mechanism listed in the project spec's Integration Points table. |
| Expose events as `AsyncStream<URL>` | Aligns with Swift 6.2 strict concurrency model. `AsyncStream` supports backpressure-free consumption, cooperative cancellation via task cancellation, and clean resource teardown when the consumer stops iterating. |
| Sendable value type for the watcher | The watcher must be `Sendable` under strict concurrency. Using a struct that owns an `AsyncStream` (created at init) with internal state managed via an actor or `DispatchQueue` satisfies this. |
| Filter `.m4a` at the watcher level | The plan scopes the watcher to `.m4a` files only. Filtering by path extension inside the watcher keeps consumers simple and matches the single responsibility described in scope. |
| Snapshot existing files at start for dedup | To implement "ignore pre-existing files" (US-02), the watcher snapshots the directory contents at initialization and excludes those paths from emission. This is cheaper and more reliable than depending on FSEvents event flags alone. |
| Coalesce via a seen-set (intra-session dedup) | A `Set<String>` of already-emitted file paths handles both the "multiple OS events for one file" edge case (slow iCloud sync) and the "each file emitted exactly once" requirement. |

---

## Tasks

### Task 0: Define the `DirectoryWatcher` Public Interface

**Layer:** Core Library

**Relevant Files:**
- `Libraries/Sources/Core/DirectoryWatcher.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/Core.swift` — understand the existing module structure and public API surface
- `Libraries/Package.swift` — confirm the Core target configuration and that CoreServices framework is available (it's a system framework, no package dependency needed)
- `spec.md` lines 54–69 — architecture summary showing where File Watcher sits in the pipeline

**Steps:**

1. [ ] Define the `DirectoryWatcher` public type with its initializer and `events` stream property
2. [ ] Define the `DirectoryWatcherError` enum for error conditions
3. [ ] Verify the file compiles: `cd Libraries && swift build`

**What to Implement:**

```swift
// The public contract other tasks build against:

/// Errors that can occur when setting up or running the directory watcher.
public enum DirectoryWatcherError: Error, Sendable {
    /// The specified directory does not exist.
    case directoryNotFound(URL)
    /// The specified path exists but is not a directory.
    case notADirectory(URL)
    /// Insufficient permissions to read the directory.
    case permissionDenied(URL)
    /// The watched directory was deleted while the watcher was running.
    case directoryDeleted(URL)
}

/// Monitors a directory for new `.m4a` files and emits their URLs via an async stream.
///
/// The watcher begins monitoring when created and stops when the `events` stream
/// is cancelled (by the consuming task being cancelled) or when the watched directory
/// is deleted.
///
/// Only files that appear *after* the watcher starts are emitted. Pre-existing files
/// are ignored. Each file path is emitted at most once per watcher session.
public struct DirectoryWatcher: Sendable {
    /// An async stream of URLs for new `.m4a` files detected in the watched directory.
    public let events: AsyncStream<URL>

    /// Creates a watcher that monitors `directory` for new `.m4a` files.
    ///
    /// - Parameter directory: The directory to watch. Must exist and be readable.
    /// - Throws: `DirectoryWatcherError` if the directory is invalid or inaccessible.
    public init(directory: URL) throws
}
```

**Acceptance Criteria:**

- GIVEN the `DirectoryWatcher.swift` file, WHEN `cd Libraries && swift build` is run, THEN compilation succeeds with no errors
- GIVEN the `DirectoryWatcher.swift` file, WHEN inspected, THEN it declares: (a) a public `init(directory: URL) throws` initializer, (b) a public `events: AsyncStream<URL>` property, (c) a public `DirectoryWatcherError` enum with cases `directoryNotFound`, `notADirectory`, `permissionDenied`, and `directoryDeleted`

**Do NOT:**
- Implement FSEvents monitoring logic — that is Task 2
- Implement filtering or dedup logic — that is Task 2
- Write any tests — Tasks 1 and 3 handle testing
- Add any dependencies to `Package.swift` — CoreServices is a system framework imported directly

---

### Task 1: Test new `.m4a` File Detection (RED)

**Layer:** Core Library
**Blocked By:** Task 0

**Relevant Files:**
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` ← create
- `Libraries/Sources/Core/DirectoryWatcher.swift` ← read only (interface from Task 0)

**Context to Read First:**
- `Libraries/Tests/CoreTests/CoreTests.swift` — existing test patterns: `@Suite`, `@Test`, `#expect`, `@testable import Core`
- `Libraries/Sources/Core/DirectoryWatcher.swift` — the public interface defined in Task 0
- `spec.md` lines 130–143 — testing strategy: Swift Testing, Arrange/Act/Assert, `@MainActor` for actor-isolated types

**Steps:**

1. [ ] Write tests for the following acceptance criteria in `DirectoryWatcherTests.swift`
2. [ ] Run tests to verify they fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Verify that test failures are compilation errors or assertion failures (not crashes), confirming the test structure is sound

**Test Implementation Guidance:**

Each test should:
- Create a temporary directory using `FileManager.default.temporaryDirectory` + a UUID subdirectory
- Create the `DirectoryWatcher` on that temporary directory
- Write `.m4a` files (empty files are fine — the watcher cares about file creation, not content)
- Collect events from the `events` stream with a timeout
- Clean up the temporary directory in a `defer` block

Use a helper pattern for collecting events with a timeout. Define this as a free function at the top of `DirectoryWatcherTests.swift` — it will be reused by Tasks 3a and 4:
```swift
/// Collect up to `count` events from the stream, waiting at most `timeout` seconds total.
func collectEvents(from stream: AsyncStream<URL>, count: Int, timeout: TimeInterval) async -> [URL]
```

**Acceptance Criteria (map to plan ACs):**

- **AC-01.1**: GIVEN a watcher on a temporary directory, WHEN a new `.m4a` file is created in that directory, THEN the file's URL is emitted on the `events` stream within 5 seconds
- **AC-01.2**: GIVEN a watcher on a temporary directory, WHEN a non-`.m4a` file is created (e.g., `.json`), THEN no event is emitted (the collected events list is empty after a reasonable timeout)
- **AC-01.3**: GIVEN a watcher on a temporary directory, WHEN 5 `.m4a` files are created in quick succession, THEN exactly 5 unique URLs are emitted (one per file, no duplicates, no drops)
- **AC-02.1**: GIVEN a temporary directory containing 3 pre-existing `.m4a` files, WHEN a watcher is created on that directory, THEN no events are emitted for those existing files (empty event list after timeout), AND when a new `.m4a` file is then created, that file's URL IS emitted

**Do NOT:**
- Implement the watcher logic — only write tests (this is the RED phase)
- Test error conditions (missing directory, permissions) — that is Task 3
- Test cancellation/cleanup behavior — that is Task 3
- Modify `DirectoryWatcher.swift` beyond what's needed to make tests compile (stub returns are acceptable)

---

### Task 2: Implement FSEvents-based Directory Monitoring (GREEN)

**Layer:** Core Library
**Blocked By:** Task 1

**Relevant Files:**
- `Libraries/Sources/Core/DirectoryWatcher.swift` ← modify (add implementation)

**Context to Read First:**
- `Libraries/Sources/Core/DirectoryWatcher.swift` — current interface from Task 0
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` — the failing tests from Task 1 that define "done"
- Apple FSEvents documentation — `FSEventStreamCreate`, `FSEventStreamScheduleWithRunLoop`, `FSEventStreamStart`, `FSEventStreamStop`, `FSEventStreamInvalidate`

**Steps:**

1. [ ] Read the failing tests from Task 1 to understand exactly what must pass
2. [ ] Implement the `DirectoryWatcher` initializer and FSEvents monitoring logic
3. [ ] Run tests to verify they pass (confirm GREEN state): `cd Libraries && swift test`
4. [ ] If any test fails, read the failure message, adjust implementation, and re-run

**Implementation Guidance:**

The `init(directory:)` should:
1. Validate the directory exists, is a directory, and is readable — throw `DirectoryWatcherError` on failure
2. Snapshot existing `.m4a` file names in the directory into a `Set<String>` (for pre-existing file exclusion)
3. Create an `AsyncStream<URL>` with a continuation
4. Start an FSEvents stream (via CoreServices `FSEventStreamCreate`) on the directory path
5. In the FSEvents callback: scan the directory for `.m4a` files, diff against the seen-set, yield new URLs via the continuation
6. Register a cancellation handler on the `AsyncStream` continuation that stops and invalidates the FSEvents stream

Key implementation details:
- **FSEvents latency**: Use a small latency value (e.g., 0.3 seconds) to coalesce rapid events without adding noticeable delay
- **Thread safety**: The FSEvents callback runs on whatever dispatch queue/runloop it's scheduled on. Use `DispatchQueue` for the FSEvents stream and synchronize the seen-set access. The `AsyncStream.Continuation` is `Sendable` and safe to call from any thread
- **Seen-set**: Maintain a `Set<String>` (file names or full paths) that starts with the pre-existing file snapshot. Add each emitted file to the set before yielding. This handles both pre-existing file exclusion and intra-session dedup
- **Directory deletion**: If a directory scan fails (e.g., directory was deleted), call `continuation.finish()` to terminate the stream gracefully
- **Sendability**: The `DirectoryWatcher` struct stores only the `AsyncStream<URL>` (which is `Sendable`). All mutable state (seen-set, FSEvents stream) lives inside the `AsyncStream`'s closure, captured by the build closure

**Acceptance Criteria:**

- GIVEN the tests from Task 1, WHEN `cd Libraries && swift test` is run, THEN all `DirectoryWatcherTests` pass
- GIVEN the implementation, WHEN `cd Libraries && swift build` is run with strict concurrency, THEN no concurrency warnings or errors

**Do NOT:**
- Add new tests — the RED tests from Task 1 define the spec
- Implement recursive directory watching — the plan explicitly excludes it
- Add retry logic — the plan explicitly excludes automatic retry
- Handle file modifications or deletions — only new file creation
- Process file contents — the watcher only detects and emits URLs

---

### Task 3a: Test Error Conditions and Cancellation (RED)

**Layer:** Core Library
**Blocked By:** Task 2

**Relevant Files:**
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` ← modify (add error/cancellation tests)
- `Libraries/Sources/Core/DirectoryWatcher.swift` ← read only

**Context to Read First:**
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` — existing test patterns and `collectEvents` helper from Task 1
- `Libraries/Sources/Core/DirectoryWatcher.swift` — current implementation from Task 2
- `plan.md` lines 66–74 — edge cases list
- `plan.md` lines 59–63 — US-03 acceptance criteria for start/stop lifecycle

**Steps:**

1. [ ] Write failing tests for the error conditions and cancellation acceptance criteria below
2. [ ] Run tests to verify the new tests fail (confirm RED state): `cd Libraries && swift test`
3. [ ] Verify that test failures are compilation errors or assertion failures (not crashes)

**Acceptance Criteria (map to plan ACs and edge cases):**

- **Directory not found**: GIVEN a URL pointing to a non-existent directory, WHEN `DirectoryWatcher(directory:)` is called, THEN it throws `DirectoryWatcherError.directoryNotFound`
- **Not a directory**: GIVEN a URL pointing to a regular file, WHEN `DirectoryWatcher(directory:)` is called, THEN it throws `DirectoryWatcherError.notADirectory`
- **Permission denied**: GIVEN a temporary directory whose POSIX permissions have been set to `0o000` via `FileManager.default.setAttributes([.posixPermissions: 0o000], ...)`, WHEN `DirectoryWatcher(directory:)` is called, THEN it throws `DirectoryWatcherError.permissionDenied` *(Note: restore permissions in a `defer` block so cleanup succeeds. Skip this test when running as root — use `try #require(getuid() != 0)`)*
- **AC-03.1 — Cancellation stops monitoring**: GIVEN a running watcher, WHEN the consuming `Task` is cancelled, THEN the `events` stream terminates (the `for await` loop exits) and no further events are emitted even if new `.m4a` files are created afterward
- **AC-03.2 — No resource leaks on cancellation**: GIVEN a running watcher, WHEN the consuming task is cancelled, THEN the FSEvents stream is stopped and invalidated *(verified by: after cancellation, creating new files produces no events, and no crash or hang occurs — resource leak testing beyond this is not practical in unit tests)*
- **Directory deleted while running**: GIVEN a running watcher on a temporary directory, WHEN the directory is deleted, THEN the `events` stream terminates gracefully (the `for await` loop exits without throwing)
- **Empty directory at startup**: GIVEN an empty directory, WHEN a watcher is created on it, THEN it starts successfully AND when a `.m4a` file is later created, that file's URL is emitted
- **File renamed away after creation**: GIVEN a running watcher, WHEN a `.m4a` file is created and then immediately renamed to a different extension, THEN the original `.m4a` URL was still emitted (the watcher does not retract events)

**Do NOT:**
- Implement any fixes — only write tests (this is the RED phase)
- Re-test basic `.m4a` detection — that is covered by Task 1/2
- Test for file modification or deletion events — out of scope
- Add UI error handling — the watcher only throws/terminates; UI surfaces errors separately

---

### Task 3b: Fix Error Conditions and Cancellation (GREEN)

**Layer:** Core Library
**Blocked By:** Task 3a

**Relevant Files:**
- `Libraries/Sources/Core/DirectoryWatcher.swift` ← modify (handle edge cases)
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` ← read only (the failing tests from Task 3a define "done")

**Context to Read First:**
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` — the failing tests from Task 3a that define what must pass
- `Libraries/Sources/Core/DirectoryWatcher.swift` — current implementation from Task 2

**Steps:**

1. [ ] Read the failing tests from Task 3a to understand exactly what must pass
2. [ ] Update the `DirectoryWatcher` implementation to handle all error conditions and edge cases
3. [ ] Run tests to verify all tests pass (confirm GREEN state): `cd Libraries && swift test`
4. [ ] If any test fails, read the failure message, adjust implementation, and re-run

**Implementation Guidance:**

Most error conditions (directory not found, not a directory, permission denied) should already be handled by the `init` validation from Task 2. The new work is likely:
- Ensuring the correct `DirectoryWatcherError` case is thrown for each condition (not a generic error)
- Handling directory deletion mid-stream: detect when a directory scan fails and call `continuation.finish()`
- The "file renamed away" edge case requires no new implementation — the seen-set dedup from Task 2 means the file was already emitted when first detected. This test should pass without changes; if not, investigate the FSEvents callback timing.

**Acceptance Criteria:**

- GIVEN the tests from Task 3a, WHEN `cd Libraries && swift test` is run, THEN all tests pass (including the new error and cancellation tests)
- GIVEN the implementation, WHEN `cd Libraries && swift build` is run with strict concurrency, THEN no concurrency warnings or errors

**Do NOT:**
- Add new tests — the RED tests from Task 3a define the spec
- Implement retry logic for transient failures — explicitly out of scope per plan
- Add UI error handling — the watcher only throws/terminates; UI surfaces errors separately
- Refactor the core monitoring logic from Task 2 unless a test requires it

---

### Task 4: Verify Full Integration and Clean Up

**Layer:** Core Library
**Blocked By:** Task 3b

**Relevant Files:**
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` ← modify (add burst test)
- `Libraries/Sources/Core/DirectoryWatcher.swift` ← read for review
- `Libraries/Sources/Core/Core.swift` ← read (no changes expected)

**Context to Read First:**
- `Libraries/Tests/CoreTests/DirectoryWatcherTests.swift` — all existing tests from Tasks 1, 3a, and 3b
- `Libraries/Sources/Core/DirectoryWatcher.swift` — full implementation from Tasks 0–3b
- `plan.md` lines 72, 80–86 — burst edge case and success criteria

**Steps:**

1. [ ] Write a burst test: create 20 `.m4a` files in rapid succession and verify all 20 URLs are emitted with no duplicates and no drops
2. [ ] Run all tests: `cd Libraries && swift test`
3. [ ] Run the full Xcode build to verify the library integrates with the app target: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build`
4. [ ] Verify all success criteria from the plan are met (checklist below)

**Success Criteria Verification Checklist (from plan.md):**
*This checklist is a verification pass confirming prior tasks' coverage — not new implementation.*

- [ ] SC-1: 100% of `.m4a` files created after watcher start are emitted (covered by Tasks 1/2 tests + burst test)
- [ ] SC-2: Zero duplicate emissions per session (covered by Tasks 1/2 dedup tests + burst test)
- [ ] SC-3: Zero emissions for pre-existing files (covered by Task 1 pre-existing file test)
- [ ] SC-4: Zero leaked resources after cancellation (covered by Task 3a/3b cancellation tests)
- [ ] SC-5: 100% error conditions produce reportable errors (covered by Task 3a/3b error tests)
- [ ] SC-6: All tests pass in library suite without full app build (covered by `cd Libraries && swift test`)

**Acceptance Criteria:**

- GIVEN 20 `.m4a` files created in rapid succession, WHEN collected from the events stream, THEN exactly 20 unique URLs are emitted
- GIVEN the full test suite, WHEN `cd Libraries && swift test` is run, THEN all tests pass
- GIVEN the Xcode project, WHEN `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build` is run, THEN the build succeeds with the library linked

**Do NOT:**
- Add integration with the app's pipeline — the watcher is a standalone library component
- Wire the watcher into `AppState` or any UI code — that is a separate plan
- Refactor the watcher API — if refactoring is needed, it should go back to planning
- Add features not in the plan (recursive watching, file content reading, cross-session dedup)

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| US-01 AC-01.1: New `.m4a` detected within 5s | Task 1 (test), Task 2 (impl) |
| US-01 AC-01.2: Non-`.m4a` files ignored | Task 1 (test), Task 2 (impl) |
| US-01 AC-01.3: Multiple files each emitted once | Task 1 (test), Task 2 (impl), Task 4 (burst) |
| US-02 AC-02.1: Pre-existing files ignored | Task 1 (test), Task 2 (impl) |
| US-03 AC-03.1: Clean stop on cancellation | Task 3a (test), Task 3b (impl) |
| US-03 AC-03.2: No resource leaks | Task 3a (test), Task 3b (impl) |
| Edge: Slow iCloud sync coalescing | Task 2 (seen-set dedup) |
| Edge: Directory not found at start | Task 3a (test), Task 3b (impl) |
| Edge: Directory deleted while running | Task 3a (test), Task 3b (impl) |
| Edge: File renamed away after creation | Task 3a (test), Task 3b (impl) |
| Edge: Rapid burst of files | Task 4 |
| Edge: Permissions error | Task 3a (test), Task 3b (impl) |
| Edge: Empty directory at startup | Task 3a (test), Task 3b (impl) |
| Success: Library tests pass independently | Task 4 |
