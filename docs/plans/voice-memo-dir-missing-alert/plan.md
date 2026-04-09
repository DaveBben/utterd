# Plan: Voice Memo Directory Missing Alert

**Status:** Complete
**Created:** 2026-04-08

---

## Why This Exists

On a fresh install, a user who has never opened Voice Memos (or has iCloud Drive
disabled) will find that the Voice Memos recordings directory does not exist on
disk. When the app launches and tries to list that directory to trigger macOS TCC
registration, the call fails silently. The app never appears in System Settings >
Full Disk Access, so the user cannot grant the permission — and the app gives no
indication of what has gone wrong. The user is stuck with no path to resolution.

---

## What We Are Building

When the app launches and the Voice Memos recordings directory does not exist, show
a specific alert explaining what the user must do (open Voice Memos to enable iCloud
sync, then relaunch the app). This is a distinct alert from the existing "Full Disk
Access not granted" alert, because the remediation step is different.

---

## Scope

### In
- Detect when the Voice Memos recordings directory is absent at launch
- Show a dedicated alert with actionable guidance (open Voice Memos, relaunch app)
- Quit the app after the user dismisses the alert (same pattern as the existing FDA alert)

### Out
- Automatic retry / polling for the directory to appear
- Detecting *why* the directory is missing (iCloud disabled vs. never-synced)
- Any changes to the Full Disk Access alert or its flow
- Any changes to what happens after Full Disk Access is successfully granted
- A button that deep-links into Voice Memos or iCloud settings

---

## Bug Description

**Reproduction steps:**
1. Fresh macOS install, Voice Memos has never been opened / iCloud Drive is off
2. Install and launch Utterd
3. Open System Settings > Privacy & Security > Full Disk Access

**Expected:** Utterd appears in the Full Disk Access list; user can toggle it on

**Actual:** Utterd does not appear in the list; TCC was never triggered because
`contentsOfDirectory` threw an error (directory absent) before TCC could register
the access attempt

---

## Acceptance Criteria

**AC1 — Directory absent, alert shown**
GIVEN the Voice Memos recordings directory does not exist,
WHEN the app finishes launching,
THEN a "Voice Memos Not Set Up" alert is shown (not the Full Disk Access alert) and the app does not start the pipeline.

**AC2 — Alert content**
GIVEN the "Voice Memos Not Set Up" alert is displayed,
WHEN the user reads it,
THEN the message text explains that Voice Memos has not synced yet and instructs them to open Voice Memos, wait for iCloud to sync, and relaunch the app.

**AC3 — Alert dismissal quits the app**
GIVEN the "Voice Memos Not Set Up" alert is displayed,
WHEN the user clicks the only button ("Quit"),
THEN the app terminates.

**AC4 — Directory present, existing flow unchanged**
GIVEN the Voice Memos recordings directory exists,
WHEN the app finishes launching,
THEN the existing permission gate logic runs exactly as before (no behavioral change).

**AC5 — Full Disk Access alert unchanged**
GIVEN the directory exists but Full Disk Access has not been granted,
WHEN the app finishes launching,
THEN the existing Full Disk Access alert is shown (not the new "Voice Memos Not Set Up" alert).

---

## Edge Cases

| Scenario | Expected Behavior |
|---|---|
| Directory exists but is empty | Existing flow (TCC fires, FDA check runs) |
| Directory path is a file, not a directory | Treated as "missing" — show Setup Required alert |
| Directory appears between process start and `evaluatePermissionGate` | Existing flow (race is harmless — directory check runs on actual state at call time) |
| User dismisses alert with Escape / keyboard shortcut | App quits (same as clicking Quit) |

---

## Success Criteria

- Zero cases where a fresh-install user sees the Full Disk Access alert when the real problem is that the directory doesn't exist
- The Setup Required alert correctly identifies the missing directory as the cause on 100% of launches where the directory is absent

---

## Technical Context

- `evaluatePermissionGate()` in `Utterd/App/AppDelegate.swift:10` is the entry point — this is where the directory check must be added
- `voiceMemoDirectoryURL` (`AppDelegate.swift:18`) is the URL being checked
- `RealFileSystemChecker.directoryExists(at:)` already implements directory existence checking via `FileManager.fileExists(atPath:isDirectory:)` — use it
- `FileSystemChecker` protocol (`Libraries/Sources/Core/FileSystemChecker.swift`) is the abstraction used in tests — the new check must go through this protocol so it remains testable with the existing mock
- The `PermissionGateAction` enum currently has two cases: `.proceed` and `.showPermissionAlert`. A third case — `.showDirectoryMissingAlert` — is needed
- `showPermissionAlert()` (`AppDelegate.swift:176`) is the pattern to follow for the new alert
- Tests for `evaluatePermissionGate` live in `UtterdTests/` — check for existing coverage to extend

---

## Dependencies & Assumptions

- The `FileSystemChecker` mock used in tests supports `directoryExists` — confirmed from protocol definition
- The directory path itself is correct and stable (`~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`)
- No sandbox entitlement is needed to check directory existence at this path (hardened runtime without sandbox is the current config)

---

## Open Questions

None — all decisions resolved during planning.

---

## Tasks

---

### Task 0 — Extend `PermissionGateAction` contract

**Goal:** Add the new enum case that signals "directory is missing" so all subsequent
tasks share a single, compiler-enforced contract.

**Files to create/modify:**
- `Utterd/App/AppDelegate.swift` — add `.showDirectoryMissingAlert` to `PermissionGateAction`

**Steps:**
1. Add `case showDirectoryMissingAlert` to the `PermissionGateAction` enum
2. Run `xcodebuild -scheme Utterd -destination 'platform=macOS' build` — the compiler
   will surface every switch on `PermissionGateAction` that needs updating, making
   scope visible before any logic changes

**Verification:**
```
xcodebuild -scheme Utterd -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning:"
```
Expected: exhaustiveness warnings/errors on every existing switch over `PermissionGateAction`
(confirms the contract change propagated correctly)

**Do NOT:**
- Implement any logic changes in this task
- Add alert UI in this task

---

### Task 1 — Gate on directory existence in `evaluatePermissionGate`

**Goal:** Detect a missing directory before attempting `contentsOfDirectory`, return
the new action, and handle it in `AppDelegate`.

**Context to read first:**
- `Utterd/App/AppDelegate.swift` — full file; understand `evaluatePermissionGate`, `applicationDidFinishLaunching`, and `showPermissionAlert` (the pattern to replicate)
- `Libraries/Sources/Core/FileSystemChecker.swift` — protocol; confirm `directoryExists` signature
- `UtterdTests/` — locate existing tests for `evaluatePermissionGate` to understand mock setup

**Files to modify:**
- `Utterd/App/AppDelegate.swift`

**Acceptance criteria:**

GIVEN `fileSystem.directoryExists(at: voiceMemoDirectoryURL)` returns `false`,
WHEN `evaluatePermissionGate` is called,
THEN it returns `.showDirectoryMissingAlert` without calling `contentsOfDirectory`.

GIVEN `fileSystem.directoryExists(at: voiceMemoDirectoryURL)` returns `true`,
WHEN `evaluatePermissionGate` is called,
THEN it calls `contentsOfDirectory` and proceeds with the existing FDA check (existing behavior preserved).

GIVEN `applicationDidFinishLaunching` receives `.showDirectoryMissingAlert`,
WHEN the action is handled,
THEN `showDirectoryMissingAlert()` is called and the pipeline is not started.

**TDD steps:**
1. Write failing tests covering the three ACs above (extend existing test file)
2. Run tests — confirm RED
3. Update `evaluatePermissionGate` to call `directoryExists` first; return `.showDirectoryMissingAlert` if false
4. Add `showDirectoryMissingAlert()` stub (can just call `NSApplication.shared.terminate(nil)` temporarily)
5. Handle `.showDirectoryMissingAlert` in the `applicationDidFinishLaunching` switch
6. Run tests — confirm GREEN

**Verification:**
```
xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -20
```

**Do NOT:**
- Write the alert UI text in this task (that's Task 2)
- Change any behavior for the directory-present path
- Add any retry or polling logic

---

### Task 2 — Implement `showDirectoryMissingAlert` UI

**Goal:** Replace the stub with a real `NSAlert` that explains the problem and quits
the app on dismissal.

**Context to read first:**
- `Utterd/App/AppDelegate.swift` — `showPermissionAlert()` at line 176; replicate its structure
- `Utterd/App/AppDelegate.swift` — `handleOpenSystemSettings()` at line 22; note the single-button + quit pattern

**Files to modify:**
- `Utterd/App/AppDelegate.swift`

**Alert spec:**
- `alertStyle`: `.informational`
- `messageText`: `"Voice Memos Not Set Up"`
- `informativeText`: `"Utterd couldn't find the Voice Memos recordings folder. Please open Voice Memos, wait for iCloud to sync, and then relaunch Utterd."`
- One button: `"Quit"` — pressing it (or Escape) terminates the app

**Acceptance criteria:**

GIVEN `showDirectoryMissingAlert()` is called,
WHEN the alert appears,
THEN `messageText` is `"Voice Memos Not Set Up"` and `informativeText` mentions opening Voice Memos and relaunching Utterd.

GIVEN the alert is displayed,
WHEN the user clicks "Quit",
THEN `NSApplication.shared.terminate(nil)` is called.

**TDD steps:**
1. Write or extend tests that verify alert properties (messageText, button title) — use the same approach as any existing alert tests
2. Run tests — confirm RED
3. Replace the stub implementation with the full `NSAlert` matching the spec above
4. Run tests — confirm GREEN

**Verification:**
```
xcodebuild -scheme Utterd -destination 'platform=macOS' test 2>&1 | tail -20
```

**Do NOT:**
- Add a button to open Voice Memos or iCloud Settings
- Add any retry logic
- Change the Full Disk Access alert

---

## Requirement Traceability

| Requirement / AC | Task |
|---|---|
| AC1 — Directory absent triggers new alert | Task 1 |
| AC2 — Alert content is actionable | Task 2 |
| AC3 — Dismissal quits the app | Task 2 |
| AC4 — Directory present, existing flow unchanged | Task 1 |
| AC5 — FDA alert unchanged | Task 1 |
| Edge: directory is a file (not a dir) | Task 1 (`directoryExists` returns false) |

---

## Completion Summary

**Completed:** 2026-04-08

- Added `.showDirectoryMissingAlert` to `PermissionGateAction` and a `guard directoryExists` pre-check in `evaluatePermissionGate`; the existing FDA flow is untouched when the directory is present
- Implemented `showDirectoryMissingAlert(showAlert:terminate:)` as a testable free function (injectable closures), matching the `handleOpenSystemSettings` pattern
- Added 11 new tests covering all ACs and edge cases; total suite is 78 tests passing
- Updated README setup steps, CHANGELOG `[Unreleased]`, and aligned mock naming across app and library test targets (2 code-review iterations)

### Leftover Issues

- `showPermissionAlert` (existing FDA alert) is not testable via dependency injection — a TODO comment was added; refactor deferred to a follow-up
- Manual launch-time verification on a fresh install (directory absent) — **verified 2026-04-08**
