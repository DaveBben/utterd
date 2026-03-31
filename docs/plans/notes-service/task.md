# Notes Service Interface — Task Breakdown

**Plan**: [docs/plans/notes-service/plan.md](plan.md)
**Date**: 2026-03-30
**Status**: In Progress

---

## Key Decisions

- **AppleScript execution via `NSAppleScript` on `@MainActor`**: Use `NSAppleScript.executeAndReturnError` rather than spawning an `osascript` process. `NSAppleScript` is in-process, avoids shell escaping concerns, and returns structured error descriptors. However, `NSAppleScript` is **not thread-safe** and must execute on the main thread. The `NSAppleScriptExecutor` uses `@MainActor` isolation via `MainActor.run` to guarantee this. Concurrent calls serialize on the main thread, which is acceptable for a single-user app processing one memo at a time. Note: `executeAndReturnError` pumps the main run loop during execution (reentrancy), but this is safe because the service holds no mutable `@MainActor` state.

- **Folder identity uses AppleScript `id` property**: Apple Notes folders have a stable `id` property (e.g., `x-coredata://...`) that persists across app restarts. The `NotesFolder` model carries `id`, `name`, and `containerID`, using `id` for equality/hashing and folder targeting. This satisfies AC-01.7 (duplicate folder names are distinguishable) and AC-02.6 (create note targets the specific folder by ID, not by name match).

- **`NotesFolder` stores its container ID for hierarchy resolution**: Each `NotesFolder` captures its parent container's ID at listing time. `resolveHierarchy` executes a single AppleScript call that returns all folders for the default account, builds an in-memory dictionary keyed by folder ID, then walks from the target folder up through `containerID` references to build the root-to-leaf path. Apple Notes' `every folder` only returns immediate children — the bulk-fetch script must recursively enumerate to capture the full tree.

- **`NoteCreationResult` enum for fallback signaling**: `createNote` returns a `NoteCreationResult` with cases `.created` and `.createdInDefaultFolder(reason:)` rather than a simple success/throw. This lets the caller distinguish normal creation from fallback (AC-02.3) without overloading the error path.

- **String escaping via a dedicated helper**: All user-supplied strings pass through `String.appleScriptEscaped` that escapes backslashes first, then double quotes, then sanitizes carriage returns (U+000D → U+000A). Order matters: backslashes must be escaped before quotes to prevent double-escaping. This is the single injection-prevention chokepoint (Success Criterion 3).

- **Testable seam via `ScriptExecutor` protocol**: To enable unit testing of error paths (AC-01.5, AC-01.6, AC-02.5) and script construction without requiring live Apple Notes, the concrete implementation depends on a `ScriptExecutor` protocol. Production uses `NSAppleScriptExecutor` (wraps `NSAppleScript` via `MainActor.run`, uses `guard let` to avoid force-unwrap); tests inject a `MockScriptExecutor` that supports sequenced results for multi-call flows (e.g., folder check then creation). Both `ScriptExecutor` and its mock live in the `Utterd`/`UtterdTests` targets (not the `Libraries` package) because `NSAppleScript` is a macOS framework API.

- **Integration tests in `UtterdTests/` with environmental guard and cleanup**: Integration tests use a `requireNotesAccess()` guard that skips gracefully when Notes is inaccessible. All test notes use UUID-prefixed titles (`UTTERD_TEST_{uuid}`). A cleanup sweep at suite start deletes orphaned test notes from prior failed runs. Per-test teardown deletes notes created by that test.

- **Verification method on the protocol**: `noteExists(title:in:)` is a protocol method (accepting `NotesFolder?`, where nil = default folder) so integration tests can verify through the same interface. Documented as test-support only.

- **Apple Events entitlement required**: The app's hardened runtime requires `com.apple.security.automation.apple-events` in `Utterd.entitlements`. `NSAppleEventsUsageDescription` must be added to `project.yml`'s `info.properties` section (the source of truth for Info.plist — direct Info.plist edits are overwritten by `xcodegen generate`).

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-01.1: List top-level folders | Task 5 (unit via MockScriptExecutor), Task 7 (integration) |
| AC-01.2: List subfolders | Task 5 (unit), Task 7 (integration) |
| AC-01.3: Resolve folder hierarchy | Task 5 (unit), Task 7 (integration) |
| AC-01.4: Empty folder list | Task 5 (unit), Task 7 (integration) |
| AC-01.5: Error when Notes inaccessible | Task 5 (unit — executor throws non-permission error) |
| AC-01.6: Permission-specific error | Task 5 (unit — executor throws automationPermissionDenied) |
| AC-01.7: Duplicate folder names distinguishable | Task 0 (NotesFolder equality by id) |
| AC-02.1: Create note in folder | Task 3 (unit), Task 6 (integration) |
| AC-02.2: Create note in default folder | Task 3 (unit), Task 6 (integration) |
| AC-02.3: Fallback to default folder | Task 3 (unit — mock returns "not found" for folder check) |
| AC-02.4: Create note when Notes not running | Task 6 (integration — Notes auto-launches) |
| AC-02.5: Error on permission denied | Task 3 (unit — executor throws automationPermissionDenied) |
| AC-02.6: Create in specific folder among duplicates | Task 3 (unit — script uses folder ID not name) |
| AC-03.1: Verify note exists after creation | Task 4 (unit), Task 6 (integration — create then verify) |
| AC-03.2: Verify note not found | Task 4 (unit), Task 6 (integration) |
| Edge: Special characters in folder names | Task 1 (escaping tests) |
| Edge: Empty note content | Task 3 (unit), Task 6 (integration) |
| Edge: Concurrent calls safe | Design (protocol is Sendable; impl serializes on @MainActor) |
| Edge: Deep folder hierarchies | Task 5 (unit — multi-level container walk) |
| Success: Zero untested ACs | All tasks (TDD) |
| Success: Protocol is sole interface | Task 0 (protocol), Task 1 (mock) |
| Success: Zero injection vulnerabilities | Task 1 (escaping tests) |

---

## Tasks

### Task 0: Define Contracts & Interfaces

**Relevant Files:**
- `Libraries/Sources/Core/NotesService.swift` <- create
- `Libraries/Sources/Core/NotesFolder.swift` <- create
- `Libraries/Sources/Core/NoteCreationResult.swift` <- create

**Context to Read First:**
- `Libraries/Sources/Core/TranscriptionService.swift` — reference protocol pattern: public, Sendable, async throws, doc comments
- `Libraries/Sources/Core/MemoStore.swift` — reference for associated error enum pattern (`MemoStoreError`)
- `Libraries/Sources/Core/MemoRecord.swift` — reference for public Sendable struct pattern with explicit init
- `docs/plans/notes-service/plan.md` — user stories and acceptance criteria that define the method signatures

**Steps:**

1. [x] Define `NotesFolder` struct in `NotesFolder.swift`: public, Sendable, with `id: String`, `name: String`, `containerID: String?` (nil = top-level). Implement `Equatable` and `Hashable` manually — equality and hashing based on `id` only (AC-01.7)
2. [x] Define `NoteCreationResult` enum in `NoteCreationResult.swift`: public, Sendable, with cases `.created` and `.createdInDefaultFolder(reason: String)`
3. [x] Define `NotesServiceError` enum in `NotesService.swift`: public, Sendable, conforming to `Error`, with cases `notesNotAccessible(String)`, `automationPermissionDenied`, `folderNotFound(String)`, `scriptExecutionFailed(String)`
4. [x] Define `NotesService` protocol in `NotesService.swift`: public, Sendable, with methods:
   - `func listFolders(in parent: NotesFolder?) async throws -> [NotesFolder]` (nil = top-level)
   - `func resolveHierarchy(for folder: NotesFolder) async throws -> [NotesFolder]` (root-to-leaf)
   - `func createNote(title: String, body: String, in folder: NotesFolder?) async throws -> NoteCreationResult` (nil = default folder)
   - `func noteExists(title: String, in folder: NotesFolder?) async throws -> Bool` (nil = default folder, test verification)
5. [x] Verify the package compiles: `cd Libraries && swift build </dev/null 2>&1`

**Acceptance Criteria:**

- GIVEN the three new files, WHEN `swift build` runs in `Libraries/`, THEN compilation succeeds with no errors
- GIVEN the `NotesService` protocol, WHEN a developer reads it, THEN every method maps to a plan user story (listFolders → US-01, createNote → US-02, noteExists → US-03)
- GIVEN two `NotesFolder` values with name "Taxes" but id "id-1" vs "id-2", WHEN compared with `==`, THEN they are not equal (AC-01.7)
- GIVEN two `NotesFolder` values with id "id-1" but names "Old" vs "New", WHEN compared with `==`, THEN they are equal (identity is by id, not name)

**Do NOT:**
- Implement any business logic — only define shapes and contracts
- Add methods beyond what the plan's user stories require
- Create the mock or the concrete implementation — those are later tasks
- Define the `ScriptExecutor` protocol here — that belongs in the Utterd target (Task 1)

---

### Task 1: AppleScript Helper, String Escaping & Entitlements

**Blocked By:** Task 0

**Relevant Files:**
- `Utterd/Core/AppleScriptNotesService.swift` <- create (helper layer + ScriptExecutor)
- `Utterd/Core/NSAppleScriptExecutor.swift` <- create
- `UtterdTests/AppleScriptEscapingTests.swift` <- create
- `UtterdTests/Mocks/MockScriptExecutor.swift` <- create
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` <- create
- `Utterd/Resources/Utterd.entitlements` <- modify
- `project.yml` <- modify (add NSAppleEventsUsageDescription)

**Context to Read First:**
- `Libraries/Sources/Core/NotesService.swift` — the protocol the mock must conform to (Task 0 output)
- `Libraries/Sources/Core/NotesFolder.swift` — types the mock handles
- `Libraries/Sources/Core/NoteCreationResult.swift` — return type for createNote
- `Utterd/Core/SpeechAnalyzerTranscriptionService.swift` — reference for concrete implementation in `Utterd/Core/`
- `Utterd/Core/RealFileSystemChecker.swift` — reference for struct implementing a Core protocol
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptionService.swift` — reference mock pattern: `@unchecked Sendable`, `nonisolated(unsafe)`, call tracking
- `UtterdTests/Mocks/MockFileSystemChecker.swift` — reference for mock placement in UtterdTests (for Utterd-target protocols)
- `Utterd/Resources/Utterd.entitlements` — current entitlements (only `com.apple.security.network.client`)
- `project.yml` — `info.properties` section is the source of truth for Info.plist values

**Steps:**

1. [x] Write failing tests for the string escaping helper:
   - Test: plain string `hello` passes through unchanged
   - Test: string `He said "hello"` → `He said \"hello\"`
   - Test: string `path\to\file` → `path\\to\\file`
   - Test: string `She said \"hi\"` (backslash-quote) → `She said \\\"hi\\\"` (backslash escaped first)
   - Test: empty string → empty string
   - Test: string with unicode/emoji passes through unchanged
   - Test: string with embedded carriage return (U+000D) → CR replaced with newline (U+000A)
2. [x] Run tests to verify they fail: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`
3. [x] Implement `String.appleScriptEscaped` computed property in `AppleScriptNotesService.swift`: replace `\` with `\\`, then `"` with `\"`, then `\r` with `\n`
4. [x] Define `ScriptExecutor` protocol in `AppleScriptNotesService.swift`: `protocol ScriptExecutor: Sendable { func execute(script: String) async throws -> String }`
5. [x] Implement `NSAppleScriptExecutor` in `NSAppleScriptExecutor.swift`: a struct conforming to `ScriptExecutor`. Execute script via `await MainActor.run { ... }`. Use `guard let script = NSAppleScript(source: source) else { throw ... }` (no force-unwrap). Detect error number -1743 → throw `NotesServiceError.automationPermissionDenied`. Other errors → throw `NotesServiceError.scriptExecutionFailed(description)`
6. [x] Create `MockScriptExecutor` in `UtterdTests/Mocks/MockScriptExecutor.swift`: `final class MockScriptExecutor: ScriptExecutor, @unchecked Sendable` with `nonisolated(unsafe) var executeResults: [Result<String, Error>] = []` (queue — each call pops the first element), `nonisolated(unsafe) var executeCalls: [String] = []`. When `executeResults` is empty, return `""`. This supports multi-call test scenarios (e.g., folder-check then creation)
7. [x] Create `MockNotesService` in `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift`: `final class MockNotesService: NotesService, @unchecked Sendable` following `MockTranscriptionService` pattern — `nonisolated(unsafe)` configurable results/errors and call-tracking arrays for each protocol method
8. [x] Add `com.apple.security.automation.apple-events` key (value `true`) to `Utterd/Resources/Utterd.entitlements`. Add `NSAppleEventsUsageDescription` to `project.yml` under `targets.Utterd.info.properties` with value `"Utterd needs permission to create notes in Apple Notes."`
9. [x] Run tests to verify escaping tests pass: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`
10. [x] Verify mock compiles: `cd Libraries && swift build --build-tests </dev/null 2>&1`

**Acceptance Criteria:**

- GIVEN a string `He said "hello"`, WHEN `appleScriptEscaped` is called, THEN the result is `He said \"hello\"`
- GIVEN a string `path\to\file`, WHEN `appleScriptEscaped` is called, THEN the result is `path\\to\\file`
- GIVEN a string `She said \"hi\"` (backslash-quote), WHEN `appleScriptEscaped` is called, THEN the result is `She said \\\"hi\\\"` (backslash escaped first)
- GIVEN a string containing a carriage return (U+000D), WHEN `appleScriptEscaped` is called, THEN the CR is replaced with a newline (U+000A)
- GIVEN an empty string, WHEN `appleScriptEscaped` is called, THEN an empty string is returned
- GIVEN `MockNotesService`, WHEN compiled with `swift build --build-tests` in `Libraries/`, THEN no errors
- GIVEN `Utterd.entitlements`, WHEN inspected, THEN it contains `com.apple.security.automation.apple-events` set to `true`
- GIVEN `project.yml`, WHEN inspected, THEN `info.properties` contains `NSAppleEventsUsageDescription`

**Do NOT:**
- Implement `NotesService` protocol methods on `AppleScriptNotesService` — those are Tasks 3–5
- Write AppleScript strings that interact with Notes.app — that starts in Task 3
- Add the `NotesService` conformance to the struct yet — just the helper layer and `ScriptExecutor`
- Place `MockScriptExecutor` in `Libraries/Tests/CoreTests/Mocks/` — it needs `ScriptExecutor` from the Utterd target

---

### Task 2: Stub AppleScriptNotesService Structure

**Blocked By:** Task 0, Task 1

**Relevant Files:**
- `Utterd/Core/AppleScriptNotesService.swift` <- modify (add struct skeleton with `ScriptExecutor` dependency)

**Context to Read First:**
- `Libraries/Sources/Core/NotesService.swift` — the protocol to implement
- `Utterd/Core/AppleScriptNotesService.swift` — existing helper layer from Task 1
- `Utterd/Core/SpeechAnalyzerTranscriptionService.swift` — reference for struct shape

**Steps:**

1. [x] Add `AppleScriptNotesService` struct declaration with a stored `ScriptExecutor` property and initializer: `struct AppleScriptNotesService { let executor: any ScriptExecutor; init(executor: any ScriptExecutor = NSAppleScriptExecutor()) }`
2. [x] Add `NotesService` conformance with placeholder method stubs that throw `fatalError("Not yet implemented")` — this establishes the struct's shape for subsequent tasks to fill in
3. [x] Verify compilation: `xcodebuild -scheme Utterd -destination 'platform=macOS' build 2>&1 | tail -20`

**Acceptance Criteria:**

- GIVEN the modified file, WHEN `xcodebuild build` runs, THEN compilation succeeds
- GIVEN `AppleScriptNotesService()`, WHEN initialized with no arguments, THEN it uses `NSAppleScriptExecutor` as default
- GIVEN `AppleScriptNotesService(executor: mockExecutor)`, WHEN initialized, THEN it accepts the injected executor

**Do NOT:**
- Implement any protocol method bodies — those are Tasks 3–5
- Add tests — this is a contracts/scaffolding task verified by compilation (like Task 0)
- Modify the `ScriptExecutor` protocol or helpers

---

### Task 3: Unit Tests & Implementation — Create Note

**Blocked By:** Task 2

**Relevant Files:**
- `Utterd/Core/AppleScriptNotesService.swift` <- modify (implement `createNote`)
- `UtterdTests/NotesServiceCreationTests.swift` <- create

**Context to Read First:**
- `Libraries/Sources/Core/NotesService.swift` — `createNote` signature and `NoteCreationResult`
- `Libraries/Sources/Core/NoteCreationResult.swift` — enum cases to return
- `Libraries/Sources/Core/NotesFolder.swift` — `NotesFolder.id` for folder targeting
- `Utterd/Core/AppleScriptNotesService.swift` — `ScriptExecutor`, `appleScriptEscaped`, struct skeleton (Tasks 1–2 output)
- `UtterdTests/Mocks/MockScriptExecutor.swift` — mock with sequenced results (Task 1 output)
- `docs/plans/notes-service/plan.md` — AC-02.1 through AC-02.6

**Steps:**

1. [x] Write failing tests using `MockScriptExecutor` injected into `AppleScriptNotesService`:
   - Test: `createNote(title:body:in: nil)` constructs script targeting default folder, returns `.created` (AC-02.2)
   - Test: `createNote` with folder reference constructs script using folder's `id` (AC-02.1)
   - Test: `createNote` with two folders having same name but different IDs — script uses the specific folder's `id`, not the name (AC-02.6)
   - Test: `createNote` when folder doesn't exist falls back — configure mock with two sequenced results: first call (folder check) returns "not found", second call (create in default) returns success → `.createdInDefaultFolder(reason:)` returned (AC-02.3)
   - Test: `createNote` when executor throws `automationPermissionDenied` → error propagated (AC-02.5)
   - Test: `createNote` with empty body constructs valid script (edge case)
   - Test: interpolated strings in script are escaped — title with quotes appears escaped in `executeCalls`
2. [x] Run tests to verify they fail: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`
3. [x] Implement `createNote(title:body:in:)`: construct AppleScript using `tell application "Notes"` to `make new note` with escaped `name` and `body`. When folder is nil, create in default folder of default account. When folder is provided, target by folder ID
4. [x] Implement folder-existence check: before creating in a specified folder, run a short script to verify the folder ID exists. If not found, create in default folder and return `.createdInDefaultFolder(reason: "Folder no longer exists")`
5. [x] Run tests to verify they pass: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`

**Acceptance Criteria:**

- GIVEN a `MockScriptExecutor` returning success, WHEN `createNote(title: "Test", body: "Content", in: nil)` is called, THEN `.created` is returned and `executeCalls` contains a script targeting the default folder
- GIVEN a folder with id `"x-coredata://ABC"`, WHEN `createNote` is called with that folder, THEN the script in `executeCalls` references that folder ID
- GIVEN two folders with name "Work" but ids "id-A" and "id-B", WHEN `createNote` is called with the first folder, THEN the script references `"id-A"`, not the name "Work" (AC-02.6)
- GIVEN `MockScriptExecutor` with results queue `[.failure(NotesServiceError.automationPermissionDenied)]`, WHEN `createNote` is called, THEN `NotesServiceError.automationPermissionDenied` is thrown (AC-02.5)
- GIVEN `MockScriptExecutor` with results `[.success("not found"), .success("ok")]` (folder check fails, default creation succeeds), WHEN `createNote` is called with a folder, THEN `.createdInDefaultFolder(reason:)` is returned (AC-02.3)
- GIVEN title `He said "hello"`, WHEN `createNote` is called, THEN the script in `executeCalls` contains properly escaped strings

**Do NOT:**
- Implement `listFolders`, `resolveHierarchy`, or `noteExists` — those are Tasks 4–5
- Test against live Apple Notes — that is Task 6
- Modify the `ScriptExecutor` protocol or `appleScriptEscaped` helper

---

### Task 4: Unit Tests & Implementation — noteExists

**Blocked By:** Task 2

**Relevant Files:**
- `Utterd/Core/AppleScriptNotesService.swift` <- modify (implement `noteExists`)
- `UtterdTests/NotesServiceVerificationTests.swift` <- create

**Context to Read First:**
- `Libraries/Sources/Core/NotesService.swift` — `noteExists` signature
- `Libraries/Sources/Core/NotesFolder.swift` — `NotesFolder.id` for targeting
- `Utterd/Core/AppleScriptNotesService.swift` — existing struct with `ScriptExecutor` and `createNote` (Tasks 1–3)
- `UtterdTests/Mocks/MockScriptExecutor.swift` — mock for injecting script results
- `docs/plans/notes-service/plan.md` — AC-03.1, AC-03.2

**Steps:**

1. [x] Write failing tests using `MockScriptExecutor`:
   - Test: `noteExists(title: "X", in: folder)` returns `true` when mock returns `"true"` (AC-03.1)
   - Test: `noteExists(title: "X", in: folder)` returns `false` when mock returns `"false"` (AC-03.2)
   - Test: `noteExists(title: "X", in: nil)` constructs script targeting default folder
   - Test: title with special characters is escaped in the script
2. [x] Run tests to verify they fail: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`
3. [x] Implement `noteExists(title:in:)`: construct AppleScript that checks if a note with the given name exists in the specified folder (by ID, or default folder if nil). Parse script output as boolean
4. [x] Run tests to verify they pass: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`

**Acceptance Criteria:**

- GIVEN a `MockScriptExecutor` returning `"true"`, WHEN `noteExists(title: "Test", in: folder)` is called, THEN `true` is returned
- GIVEN a `MockScriptExecutor` returning `"false"`, WHEN `noteExists(title: "Missing", in: folder)` is called, THEN `false` is returned
- GIVEN nil folder, WHEN `noteExists` is called, THEN `executeCalls` contains a script targeting the default folder
- GIVEN title `O'Brien's "Notes"`, WHEN `noteExists` is called, THEN the script contains properly escaped title

**Do NOT:**
- Return note content — only existence check (plan excludes full note reading)
- Implement `listFolders` or `resolveHierarchy` — that is Task 5
- Test against live Apple Notes — that is Task 6

---

### Task 5: Unit Tests & Implementation — List Folders & Resolve Hierarchy

**Blocked By:** Task 2

**Relevant Files:**
- `Utterd/Core/AppleScriptNotesService.swift` <- modify (implement `listFolders` and `resolveHierarchy`)
- `UtterdTests/NotesServiceListingTests.swift` <- create

**Context to Read First:**
- `Libraries/Sources/Core/NotesService.swift` — `listFolders` and `resolveHierarchy` signatures
- `Libraries/Sources/Core/NotesFolder.swift` — `NotesFolder` with `id`, `name`, `containerID`
- `Utterd/Core/AppleScriptNotesService.swift` — existing struct and helpers (Tasks 1–4)
- `UtterdTests/Mocks/MockScriptExecutor.swift` — mock for injecting delimited script output
- `docs/plans/notes-service/plan.md` — AC-01.1 through AC-01.7

**Steps:**

1. [x] Write failing tests using `MockScriptExecutor`:
   - Test: `listFolders(in: nil)` parses mock output `"id1\tFinance\t\nid2\tPersonal\t\n"` into two `NotesFolder` structs with correct `id`, `name`, `containerID` (AC-01.1)
   - Test: `listFolders(in: parentFolder)` constructs script referencing parent's ID and returns children (AC-01.2)
   - Test: `listFolders` with empty mock output returns empty array (AC-01.4)
   - Test: `listFolders` when executor throws non-permission error → throws `notesNotAccessible` (AC-01.5)
   - Test: `listFolders` when executor throws `automationPermissionDenied` → error propagated (AC-01.6)
   - Test: `resolveHierarchy` for top-level folder (containerID nil) returns single-element array
   - Test: `resolveHierarchy` for nested folder — mock returns bulk output `"parentId\tFinance\t\nchildId\tTaxes\tparentId\n"`, given folder with id `"childId"` and containerID `"parentId"`, result is `[finance, taxes]` in root-to-leaf order (AC-01.3)
   - Test: `resolveHierarchy` for deeply nested folder (3 levels) returns correct path (edge: deep hierarchies)
   - Test: `resolveHierarchy` when containerID references unknown folder → throws `folderNotFound`
2. [x] Run tests to verify they fail: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`
3. [x] Implement `listFolders(in:)`: construct AppleScript using `tell application "Notes"`. For nil parent, get top-level folders of default account. For a specific parent, get child folders of that folder by ID. Return each folder's `id`, `name`, and container `id` as tab-delimited fields, one folder per line. Parse the output into `[NotesFolder]` structs. Apple Notes' `every folder` only returns immediate children — this is correct for the `listFolders` API contract
4. [x] Implement `resolveHierarchy(for:)`: execute a single AppleScript call that returns all folders for the default account (id, name, containerID for each — recursive enumeration). Build a `[String: NotesFolder]` dictionary keyed by folder ID. Starting from the given folder, walk up through `containerID` references, collecting ancestors. Reverse the collected array to produce root-to-leaf order. If a `containerID` is not found in the dictionary, throw `NotesServiceError.folderNotFound`
5. [x] Remove the `fatalError` stubs from Task 2 — all four protocol methods now have real implementations
6. [x] Run tests to verify they pass: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`

**Acceptance Criteria:**

- GIVEN mock output `"id1\tFinance\t\nid2\tPersonal\t\n"`, WHEN `listFolders(in: nil)` is called, THEN two `NotesFolder` structs are returned: `(id: "id1", name: "Finance", containerID: nil)` and `(id: "id2", name: "Personal", containerID: nil)`
- GIVEN a parent folder with id `"id1"`, WHEN `listFolders(in: parent)` is called, THEN `executeCalls` contains a script referencing `folder id "id1"`
- GIVEN empty mock output, WHEN `listFolders(in: nil)` is called, THEN an empty array is returned (AC-01.4)
- GIVEN mock throws a generic error, WHEN `listFolders` is called, THEN `NotesServiceError.notesNotAccessible` is thrown (AC-01.5)
- GIVEN mock throws `NotesServiceError.automationPermissionDenied`, WHEN `listFolders` is called, THEN the same error is propagated (AC-01.6)
- GIVEN mock returns `"parentId\tFinance\t\nchildId\tTaxes\tparentId\n"` for all-folders query, WHEN `resolveHierarchy(for: NotesFolder(id: "childId", name: "Taxes", containerID: "parentId"))` is called, THEN `[NotesFolder(id: "parentId", name: "Finance", ...), NotesFolder(id: "childId", name: "Taxes", ...)]` is returned in root-to-leaf order (AC-01.3)
- GIVEN a folder with `containerID` referencing a non-existent ID in the all-folders output, WHEN `resolveHierarchy` is called, THEN `NotesServiceError.folderNotFound` is thrown

**Do NOT:**
- Create or rename folders — the service is read-only for folder structure
- Include the default Notes folder in listings (plan decision: excluded)
- Modify `createNote` or `noteExists` — those are done in Tasks 3–4
- Test against live Apple Notes — that is Task 7

---

### Task 6: Integration Tests — Note Creation & Verification

**Blocked By:** Task 3, Task 4

**Relevant Files:**
- `UtterdTests/AppleScriptNotesServiceIntegrationTests.swift` <- create

**Context to Read First:**
- `Utterd/Core/AppleScriptNotesService.swift` — the concrete implementation to test
- `Utterd/Core/NSAppleScriptExecutor.swift` — the real executor
- `Libraries/Sources/Core/NotesService.swift` — protocol contract
- `Libraries/Sources/Core/NoteCreationResult.swift` — expected return types
- `docs/plans/notes-service/plan.md` — AC-02.1, AC-02.2, AC-02.4, AC-03.1, AC-03.2

**Steps:**

1. [ ] Write integration test infrastructure and failing tests:
   - Create `requireNotesAccess()` helper: attempt `tell application "Notes" to name of default account` via `NSAppleScriptExecutor` — if it fails, skip with a descriptive message
   - Create cleanup sweep: at suite start, find and delete notes with `UTTERD_TEST_` prefix from previous failed runs
   - Test: create note in default folder → `.created` returned, `noteExists` confirms it (AC-02.2, AC-03.1)
   - Test: create note with empty body succeeds (edge case)
   - Test: create note with special characters in title/body succeeds and `noteExists` finds it
   - Test: `noteExists` for a UUID title never created returns `false` (AC-03.2)
   - Test: create note succeeds regardless of Notes app state — Notes auto-launches (AC-02.4)
   - Add per-test teardown deleting created test notes
2. [ ] Run tests to verify they fail: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`
3. [ ] Wire tests using `AppleScriptNotesService(executor: NSAppleScriptExecutor())` — real implementation with real Notes access
4. [ ] Run tests to verify they pass: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`

**Acceptance Criteria:**

- GIVEN Notes is accessible, WHEN `createNote(title: "UTTERD_TEST_{uuid}", body: "test", in: nil)` is called, THEN `.created` is returned and `noteExists(title:in:nil)` returns `true` (AC-02.2, AC-03.1)
- GIVEN an empty body string, WHEN `createNote` is called, THEN the note is created successfully
- GIVEN a UUID title never created, WHEN `noteExists` is called, THEN `false` is returned (AC-03.2)
- GIVEN Notes is not running, WHEN `createNote` is called, THEN the note is still created (Notes auto-launches) (AC-02.4)
- GIVEN Notes is not accessible, WHEN the test suite starts, THEN all tests are skipped gracefully
- GIVEN a prior test run left orphan notes, WHEN the suite starts, THEN `UTTERD_TEST_` prefixed notes are cleaned up

**Do NOT:**
- Test folder listing — that is Task 7
- Leave test notes in Notes.app — cleanup via sweep + teardown
- Assume Notes is available — always guard with `requireNotesAccess()`

---

### Task 7: Integration Tests — Folder Listing & Hierarchy

**Blocked By:** Task 5, Task 6

**Relevant Files:**
- `UtterdTests/AppleScriptNotesServiceIntegrationTests.swift` <- modify (add folder tests)

**Context to Read First:**
- `Utterd/Core/AppleScriptNotesService.swift` — the concrete implementation
- `Libraries/Sources/Core/NotesFolder.swift` — `NotesFolder` properties to validate
- `UtterdTests/AppleScriptNotesServiceIntegrationTests.swift` — existing integration suite from Task 6
- `docs/plans/notes-service/plan.md` — AC-01.1 through AC-01.4

**Steps:**

1. [ ] Write failing integration tests (reuse `requireNotesAccess()` guard from Task 6):
   - Test: `listFolders(in: nil)` returns a `[NotesFolder]` array (may be empty — assert type and shape) (AC-01.1, AC-01.4)
   - Test: each returned folder has non-empty `id` and non-empty `name`
   - Test: if folders are returned, `resolveHierarchy` for the first folder returns at least a single-element array containing that folder
   - Test: if a folder has subfolders, `listFolders(in: folder)` returns children (environment-dependent — skip if no nested folders found)
2. [ ] Run tests to verify they fail: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`
3. [ ] Wire tests using the real `AppleScriptNotesService` with `NSAppleScriptExecutor`
4. [ ] Run tests to verify they pass: `xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -30`

**Acceptance Criteria:**

- GIVEN Notes is accessible, WHEN `listFolders(in: nil)` is called, THEN a `[NotesFolder]` array is returned (may be empty) (AC-01.1, AC-01.4)
- GIVEN folders are returned, WHEN examining each folder, THEN `id` is non-empty and `name` is non-empty
- GIVEN at least one folder exists, WHEN `resolveHierarchy` is called for it, THEN the result contains at least that folder
- GIVEN Notes is not accessible, WHEN the test suite starts, THEN tests are skipped gracefully

**Do NOT:**
- Create or delete folders in Notes — the service is read-only for folder structure
- Assert specific folder names — the user's folder structure is not known at test time
- Modify the concrete implementation — it should be complete from Task 5
