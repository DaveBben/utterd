# Full Disk Access Permission Gate — Task Breakdown

**Plan**: [plan.md](plan.md)
**Date**: 2026-03-28
**Status**: In Progress

---

## Key Decisions

- **Permission check location**: The permission-check model lives in the app target (`Utterd/Core/`), not in `Libraries/`. The plan explicitly scopes out changes to `Libraries/`, and the check is app-specific behavior (voice memo directory access), not reusable library logic. The model uses the existing `FileSystemChecker` protocol from `Libraries/` via `import Core`.

- **Alert implementation**: Use `NSAlert` via AppKit, not a SwiftUI `.alert()` modifier. The gate must block the main UI from ever appearing and must terminate the app after either button. `NSAlert` with `runModal()` gives full control over modality and dismiss behavior. SwiftUI alerts cannot suppress Escape dismissal reliably. The alert is presented from `applicationDidFinishLaunching(_:)` via `NSApplicationDelegateAdaptor` — this fires after the run loop is active but before the SwiftUI window becomes visible, avoiding the `runModal()` transaction conflict that occurs when called from within SwiftUI's `body` evaluation.

- **Escape key behavior**: Bind Escape to the "Quit" button (`keyEquivalent = "\u{1b}"`). Without a key equivalent bound to Escape, NSAlert plays a system beep on every Escape press — functional but jarring UX. Binding Escape to "Quit" follows macOS convention (Escape = the safe/cancel action) and eliminates the beep. Note: plan AC-02.4 says "the alert remains on screen and cannot be dismissed." Binding Escape to Quit satisfies the intent of AC-02.4 — the user cannot bypass the gate and reach the main UI — though the mechanism is termination rather than keeping the alert visible. This is strictly better UX.

- **AppDelegate owns PermissionChecker**: The `AppDelegate` creates its own `PermissionChecker(fileSystem: RealFileSystemChecker())` internally rather than receiving one from `UtterdApp`. This is simpler because `@NSApplicationDelegateAdaptor` creates the delegate instance itself — constructor injection from `UtterdApp` is not possible. The `PermissionChecker` lives for the app's lifetime (the delegate does) but is only used at launch.

- **Mock strategy for AC-04.3**: Extend the test double pattern with a recording mock that captures the URLs passed to `isReadable(at:)`. This is a new mock in `UtterdTests/Mocks/`, not a modification to the existing `MockFileSystemChecker` in `Libraries/Tests/` (which the plan says not to change). The new mock conforms to `FileSystemChecker` from the `Core` module via `import Core`.

- **Sandbox removal approach**: Remove only `com.apple.security.app-sandbox` from `Utterd.entitlements`. Keep `com.apple.security.network.client` — it remains valid outside the sandbox per Apple docs and plan assumptions.

- **RealFileSystemChecker placement**: The production `FileSystemChecker` conformance lives in its own file (`Utterd/Core/RealFileSystemChecker.swift`), not inside `PermissionChecker.swift`. All four protocol methods are fully implemented wrapping `FileManager` — no stubs. This type will also be needed when wiring up the real `VoiceMemoWatcher` in a future change.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-01.1 (sandbox absent from signed binary) | Task 1 |
| AC-02.1 (modal alert on missing access) | Task 4 |
| AC-02.2 (Open System Settings + terminate) | Task 4 |
| AC-02.3 (Quit terminates immediately) | Task 4 |
| AC-02.4 (alert not dismissable via Escape/Cmd-W) | Task 4 (Escape bound to Quit — user cannot bypass gate; Command-W beeps on modal panel. See Key Decisions for AC-02.4 reconciliation) |
| AC-02.5 (uses actual voice memo directory path) | Task 2 |
| AC-03.1 (normal launch when access granted) | Task 4 |
| AC-04.1 (test: readable → access available) | Task 2 |
| AC-04.2 (test: not readable → access unavailable) | Task 2 |
| AC-04.3 (test: correct directory path checked) | Task 2 |
| Edge E1 (directory doesn't exist) | Task 2 (AC — `isReadable` returns `false` for nonexistent paths) |
| Edge E2 (not readable for other reasons) | Task 2 (AC — same code path as E1) |
| Edge E3 (URL scheme fails to open) | Task 4 (AC) |
| Edge E4 (user grants access, no relaunch) | Out of scope per plan — no task needed |
| Edge E5 (non-standard home directory) | Task 2 (AC) |

---

## Tasks

### Task 0: Define Contracts & Interfaces

**Relevant Files:**
- `Utterd/Core/PermissionChecker.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/FileSystemChecker.swift` — the `FileSystemChecker` protocol this model depends on; understand the `isReadable(at:)` method signature and `Sendable` conformance
- `Utterd/Core/AppState.swift` — understand the `@Observable` / `@MainActor` pattern used in the app target

**Steps:**

1. [x] Create `Utterd/Core/PermissionChecker.swift` with `import Core` at the top (this is the first usage of a `Core` type in the app target — the `Utterd` target already declares a dependency on `Core` in `project.yml`)
2. [x] Define `PermissionChecker` as an `@Observable @MainActor` class with:
   - A stored property `hasVoiceMemoAccess: Bool` initialized to `false` (assume no access until proven otherwise — prevents the main UI from flashing before the check completes)
   - An initializer that accepts a `FileSystemChecker` dependency and stores it
   - A computed property `voiceMemoDirectoryURL: URL` that builds `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/` using `FileManager.default.homeDirectoryForCurrentUser`
   - A `checkAccess()` method that calls `fileSystem.isReadable(at: voiceMemoDirectoryURL)` and assigns the result to `hasVoiceMemoAccess`
3. [x] Verify the file compiles: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build`

**Acceptance Criteria:**

- GIVEN the `PermissionChecker` class, WHEN compiled, THEN it has: (1) a stored property `hasVoiceMemoAccess: Bool` defaulting to `false`, (2) an initializer accepting a `FileSystemChecker` parameter, (3) a `checkAccess()` method, and (4) a computed property `voiceMemoDirectoryURL: URL`. The build succeeds
- GIVEN the class file, WHEN inspected, THEN it has `import Core` at the top

**Do NOT:**
- Write tests — Task 0 is verified by compilation only; tests are Task 2's responsibility
- Implement the alert UI — that is Task 4
- Add `PermissionChecker` to `UtterdApp.swift` — that is Task 4
- Modify any files in `Libraries/` — out of scope per plan
- Modify any Swift source files other than the new `PermissionChecker.swift`

---

### Task 1: Disable App Sandbox in Entitlements

> **TDD-exempt** — this task modifies a configuration file (XML plist) with no directly unit-testable behavior. Correctness is verified by build success and XML inspection.

**Relevant Files:**
- `Utterd/Resources/Utterd.entitlements` ← modify

**Context to Read First:**
- `Utterd/Resources/Utterd.entitlements` — current entitlements with sandbox enabled; understand what keys exist
- `project.yml` — confirm the entitlements file path is referenced correctly

**Steps:**

1. [x] Remove the `com.apple.security.app-sandbox` key and its `<true/>` value from `Utterd.entitlements`
2. [x] Keep `com.apple.security.network.client` intact
3. [x] Regenerate and build: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build`

**Acceptance Criteria:**

- GIVEN the modified entitlements file, WHEN its XML is inspected, THEN `com.apple.security.app-sandbox` is absent and `com.apple.security.network.client` remains present with value `true`
- GIVEN the app is built, WHEN the build completes, THEN it succeeds without errors

**Do NOT:**
- Remove `com.apple.security.network.client` — it is still needed
- Modify `project.yml` — the entitlements path does not change
- Add any new entitlement keys — only remove the sandbox key
- Modify any Swift source files — that is Tasks 0, 2, 3, 4

---

### Task 2: Implement PermissionChecker Model with Tests

**Blocked By:** Task 0

**Relevant Files:**
- `Utterd/Core/PermissionChecker.swift` ← modify (flesh out implementation)
- `UtterdTests/PermissionCheckerTests.swift` ← create
- `UtterdTests/Mocks/MockFileSystemChecker.swift` ← create (recording mock for app-level tests)

**Context to Read First:**
- `Utterd/Core/PermissionChecker.swift` — the contract defined in Task 0; understand the class shape, `checkAccess()` method, and `voiceMemoDirectoryURL` property
- `Libraries/Sources/Core/FileSystemChecker.swift` — the protocol the mock must conform to; note all four method signatures
- `Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift` — the existing mock pattern to follow (but do NOT modify this file); note the `@unchecked Sendable` + `nonisolated(unsafe)` pattern
- `UtterdTests/AppStateTests.swift` — the test structure pattern used in app-level tests (`@Suite`, `@Test`, `@MainActor`, `#expect`)

**Steps:**

1. [x] Write failing tests in `PermissionCheckerTests.swift` (add `import Core` and `@testable import Utterd` at the top):
   - Test 1 (AC-04.1): Create mock with `readableResult = true`, init `PermissionChecker` with it, call `checkAccess()`, assert `hasVoiceMemoAccess == true`
   - Test 2 (AC-04.2 + E1 + E2): Create mock with `readableResult = false`, init `PermissionChecker` with it, call `checkAccess()`, assert `hasVoiceMemoAccess == false`. Add a comment noting this covers both E1 (directory doesn't exist) and E2 (not readable for other reasons) because `isReadable` returns `false` in both cases
   - Test 3 (AC-04.3): Assert that `permissionChecker.voiceMemoDirectoryURL.path` ends with `Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings` — this tests path construction as a pure output without needing a recording mock. Additionally, create a recording mock, call `checkAccess()`, and assert `isReadableCalledWith` contains the `voiceMemoDirectoryURL` — confirming `checkAccess()` actually uses the correct URL
2. [x] Create `UtterdTests/Mocks/MockFileSystemChecker.swift` with `import Core` at the top. Build a recording mock conforming to `FileSystemChecker` that:
   - Has `readableResult: Bool` (configurable return value)
   - Has `isReadableCalledWith: [URL]` array that records every URL passed to `isReadable(at:)`
   - Implements `directoryExists`, `contentsOfDirectory`, `fileSize` with sensible defaults (return `true`, `[]`, `nil` respectively)
   - Follows the `@unchecked Sendable` + `nonisolated(unsafe)` pattern from the Libraries mock
   - Add a comment: `// NOTE: Parallels Libraries/Tests/CoreTests/Mocks/MockFileSystemChecker.swift. If FileSystemChecker gains new methods, both mocks must be updated.`
3. [x] Run tests to verify they fail (confirm RED state): `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`
4. [x] Implement `checkAccess()` in `PermissionChecker.swift`: call `fileSystem.isReadable(at: voiceMemoDirectoryURL)` and assign the result to `hasVoiceMemoAccess`
5. [x] Verify `voiceMemoDirectoryURL` uses `FileManager.default.homeDirectoryForCurrentUser` to expand the path (not a hardcoded `/Users/<name>/` prefix) — satisfying E5
6. [x] Run tests to verify they pass (confirm GREEN state): `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`

**Acceptance Criteria:**

- GIVEN a mock `FileSystemChecker` where `isReadable` returns `true`, WHEN `checkAccess()` is called, THEN `hasVoiceMemoAccess` is `true`
- GIVEN a mock `FileSystemChecker` where `isReadable` returns `false`, WHEN `checkAccess()` is called, THEN `hasVoiceMemoAccess` is `false` (this single code path covers E1 and E2)
- GIVEN a `PermissionChecker` instance, WHEN `voiceMemoDirectoryURL.path` is inspected, THEN it ends with `Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`
- GIVEN a recording mock, WHEN `checkAccess()` is called, THEN `isReadable` was called with `voiceMemoDirectoryURL`
- GIVEN the `voiceMemoDirectoryURL` property, WHEN inspected, THEN it uses `FileManager.default.homeDirectoryForCurrentUser` — not a hardcoded user path

**Do NOT:**
- Implement the alert UI — that is Task 4
- Modify files in `Libraries/` or `Libraries/Tests/` — the plan explicitly excludes changes there
- Add `PermissionChecker` to `UtterdApp.swift` — that is Task 4
- Test the alert behavior — that is Task 4's scope

---

### Task 3: Add RealFileSystemChecker Production Conformance

**Blocked By:** Task 0

**Relevant Files:**
- `Utterd/Core/RealFileSystemChecker.swift` ← create
- `UtterdTests/RealFileSystemCheckerTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/FileSystemChecker.swift` — the protocol to conform to; all four methods must be implemented
- `Utterd/Core/PermissionChecker.swift` — understand how `RealFileSystemChecker` will be injected as the `FileSystemChecker` dependency

**Steps:**

1. [x] Write a failing test in `UtterdTests/RealFileSystemCheckerTests.swift` that verifies `RealFileSystemChecker` conforms to `FileSystemChecker` and that `isReadable(at:)` returns `true` for a known-readable path (e.g., `FileManager.default.temporaryDirectory`) and `false` for a nonexistent path (use a UUID-based path like `/tmp/\(UUID().uuidString)` to avoid accidental collisions)
2. [x] Run tests to verify they fail (confirm RED state): `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`
3. [x] Create `Utterd/Core/RealFileSystemChecker.swift` with `import Core` and `import Foundation`. Define `struct RealFileSystemChecker: FileSystemChecker` implementing all four protocol methods:
   - `isReadable(at:)` → `FileManager.default.isReadableFile(atPath: url.path)`
   - `directoryExists(at:)` → `FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)` checking `isDir`
   - `contentsOfDirectory(at:)` → `(try? FileManager.default.contentsOfDirectory(at: url, ...)) ?? []`
   - `fileSize(at:)` → `(try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)`
4. [x] Run tests to verify they pass (confirm GREEN state): `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`

**Acceptance Criteria:**

- GIVEN `RealFileSystemChecker`, WHEN compiled, THEN it conforms to `FileSystemChecker` with all four methods implemented (no stubs or `fatalError`)
- GIVEN a temporary directory that exists and is readable, WHEN `isReadable(at:)` is called, THEN it returns `true`
- GIVEN a nonexistent path, WHEN `isReadable(at:)` is called, THEN it returns `false`

**Do NOT:**
- Place this struct inside `PermissionChecker.swift` — it is a general-purpose type that `VoiceMemoWatcher` will also use in the future
- Modify files in `Libraries/` — out of scope per plan
- Wire this into `UtterdApp.swift` — that is Task 4

---

### Task 4: Wire Permission Gate into App Launch with Blocking Alert

**Blocked By:** Task 1, Task 2, Task 3

**Relevant Files:**
- `Utterd/App/UtterdApp.swift` ← modify
- `Utterd/App/AppDelegate.swift` ← create (NSApplicationDelegateAdaptor for pre-UI permission gate)
- `UtterdTests/PermissionGateTests.swift` ← create

**Context to Read First:**
- `Utterd/App/UtterdApp.swift` — current app entry point structure; understand the `@State appState` and scene layout
- `Utterd/Core/PermissionChecker.swift` — the model from Task 0/2; understand the `checkAccess()` API and `hasVoiceMemoAccess` property
- `Utterd/Core/RealFileSystemChecker.swift` — the production conformance from Task 3 to inject into `PermissionChecker`
- `Libraries/Sources/Core/FileSystemChecker.swift` — the protocol for reference
- `Utterd/App/ContentView.swift` — the main UI that must NOT appear when access is denied
- `UtterdTests/Mocks/MockFileSystemChecker.swift` — the recording mock from Task 2, needed for unit tests in this task

**Steps:**

1. [ ] Write failing tests in `UtterdTests/PermissionGateTests.swift` (add `import Core` and `@testable import Utterd`). The tests target two free functions that will be defined in `AppDelegate.swift`:
   - Define an enum `PermissionGateAction { case proceed, showPermissionAlert }` in `AppDelegate.swift` (or a separate file). Define a function `evaluatePermissionGate(checker: PermissionChecker) -> PermissionGateAction` that calls `checker.checkAccess()` and returns `.showPermissionAlert` if `hasVoiceMemoAccess` is `false`, `.proceed` otherwise. Define a function `handleOpenSystemSettings(openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }, terminate: () -> Void = { NSApplication.shared.terminate(nil) })` that attempts to open the Full Disk Access URL and always calls `terminate` regardless of the `openURL` result.
   - Test 1: Given a mock where `isReadable` returns `false`, when `evaluatePermissionGate(checker:)` is called, then the result is `.showPermissionAlert`
   - Test 2: Given a mock where `isReadable` returns `true`, when `evaluatePermissionGate(checker:)` is called, then the result is `.proceed`
   - Test 3 (E3): Given an `openURL` closure that returns `false` (simulating scheme failure) and a recording `terminate` closure, when `handleOpenSystemSettings(openURL:terminate:)` is called, then `terminate` was called exactly once
2. [ ] Run tests to verify they fail (confirm RED state): `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`
3. [ ] Create `Utterd/App/AppDelegate.swift` containing:
   - The `PermissionGateAction` enum and the two testable functions described in Step 1
   - An `AppDelegate: NSObject, NSApplicationDelegate` class that creates its own `PermissionChecker(fileSystem: RealFileSystemChecker())` internally (the delegate is instantiated by `@NSApplicationDelegateAdaptor`, so constructor injection from `UtterdApp` is not possible)
   - In `applicationDidFinishLaunching(_:)`: guard against XCTest (`ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil` → return early; add comment: "Works with xcodebuild. Does not detect swift test CLI."). Then call `evaluatePermissionGate(checker:)` and, if `.showPermissionAlert`, call `showPermissionAlert()`
4. [ ] Implement `showPermissionAlert()` as a private method on `AppDelegate`:
   - Create `NSAlert()` with `alertStyle = .warning`
   - Set `messageText = "Full Disk Access Required"`
   - Set `informativeText` explaining that Utterd needs to read voice memos from iCloud, and the user must grant Full Disk Access in System Settings then relaunch
   - Add button 1: `addButton(withTitle: "Open System Settings")` — no special key equivalent
   - Add button 2: `addButton(withTitle: "Quit")` — set `keyEquivalent = "\u{1b}"` (Escape) so pressing Escape triggers Quit, eliminating the system beep
   - Call `runModal()` synchronously
   - After `runModal()` returns: if response is `.alertFirstButtonReturn`, call `handleOpenSystemSettings()` (which opens the URL and terminates). For any other response (Quit/Escape), call `NSApplication.shared.terminate(nil)` directly
5. [ ] In `UtterdApp.swift`: add only `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate` — no other changes needed since `AppDelegate` owns its own `PermissionChecker`
6. [ ] Run tests to verify they pass (confirm GREEN state): `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`

**Acceptance Criteria:**

- GIVEN a mock where `isReadable` returns `false`, WHEN `evaluatePermissionGate(checker:)` is called, THEN it returns `.showPermissionAlert` (unit tested)
- GIVEN a mock where `isReadable` returns `true`, WHEN `evaluatePermissionGate(checker:)` is called, THEN it returns `.proceed` (unit tested)
- GIVEN an `openURL` closure that returns `false`, WHEN `handleOpenSystemSettings(openURL:terminate:)` is called, THEN `terminate` is called exactly once (unit tested — covers E3)
- GIVEN the alert is displayed, WHEN the user clicks "Open System Settings", THEN the app opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` and terminates (manual)
- GIVEN the alert is displayed, WHEN the user clicks "Quit", THEN the app terminates immediately (manual)
- GIVEN the alert is displayed, WHEN the user presses Escape, THEN the "Quit" button is activated (Escape is bound to Quit via key equivalent) and the app terminates (manual)
- GIVEN the app is running under XCTest, WHEN `applicationDidFinishLaunching` fires, THEN no alert is presented (prevents test hangs)
- GIVEN the permission check and alert are triggered from `applicationDidFinishLaunching(_:)` via `NSApplicationDelegateAdaptor`, WHEN the app launches without access, THEN the alert appears before the SwiftUI window renders. Note: if the main window flashes briefly behind the alert during manual testing, add `NSApp.windows.forEach { $0.orderOut(nil) }` before `runModal()` as a refinement

**Do NOT:**
- Add runtime re-checking or polling for permission changes — out of scope per plan
- Modify the `VoiceMemoWatcher` or any files in `Libraries/` — out of scope per plan
- Add any other permission checks (EventKit, Automation) — out of scope per plan
- Migrate to `MenuBarExtra` — that is separate work
- Call `NSAlert.runModal()` from within SwiftUI's `body` or from `App.init()` — this causes transaction conflicts. Use `applicationDidFinishLaunching` via the delegate adaptor
