# Plan: Full Disk Access Permission Gate

**Status**: Approved
**Created**: 2026-03-28
**Branch**: `permissions`

---

## What We Are Building

A startup gate that checks whether Utterd can read the iCloud Voice Memos directory. If it cannot, the app shows a blocking alert explaining that Full Disk Access is required, with options to open System Settings or quit. The app sandbox is also disabled so the app can access files outside its container. The user must grant Full Disk Access and relaunch — the app does not auto-detect the permission change.

---

## Why This Exists

When Utterd cannot read voice memos, it polls indefinitely but gives the user no indication that something is wrong. The user has no way to distinguish a configuration problem from normal startup delay, so the app appears broken with no path to recovery. This change makes the failure visible so the user can take action.

---

## In Scope

- Disabling the app sandbox (remove `com.apple.security.app-sandbox` from entitlements)
- Adding a startup permission check on the actual voice memo directory
- Displaying a non-dismissable alert when the check fails
- Deep-linking to System Settings > Privacy & Security > Full Disk Access
- Quitting the app after either alert action
- Automated tests for the permission-check model

## Out of Scope

- Automatically detecting when the user grants permission (requires relaunch)
- Runtime re-checking or polling for permission changes while the app is open
- Requesting or handling any other permissions (EventKit, Automation, etc.)
- Migrating to `MenuBarExtra` scene (separate work)
- Any changes to the `VoiceMemoWatcher` or `Libraries/` package

---

## User Stories

### US-01: App launches without sandbox restrictions

As a user running Utterd outside the App Store,
I want the app to run without sandbox restrictions,
So that it can access the iCloud Voice Memos directory.

- [ ] AC-01.1: GIVEN the app is built, WHEN I inspect the signed binary with `codesign -d --entitlements -`, THEN `com.apple.security.app-sandbox` is absent from the output.

### US-02: Blocked launch when Full Disk Access is missing

As a user who has not yet granted Full Disk Access,
I want to see a clear explanation of what is needed and why,
So that I know how to fix the problem instead of wondering why nothing happens.

- [ ] AC-02.1: GIVEN Full Disk Access is NOT granted, WHEN the app launches, THEN a modal alert appears before the main UI is shown. The alert title is "Full Disk Access Required" and the message explains that Utterd needs to read voice memos from iCloud and the user must grant access in System Settings then relaunch.
- [ ] AC-02.2: GIVEN the alert is displayed, WHEN the user clicks "Open System Settings", THEN the app opens the Full Disk Access pane (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`) and terminates. The termination must not occur until the open call has completed.
- [ ] AC-02.3: GIVEN the alert is displayed, WHEN the user clicks "Quit", THEN the app terminates immediately.
- [ ] AC-02.4: GIVEN the alert is displayed, WHEN the user attempts to dismiss the alert without clicking a button (e.g., Escape key, Command-W), THEN the alert remains on screen and cannot be dismissed. The only path forward is clicking one of the two buttons. The user cannot reach the main UI without Full Disk Access.
- [ ] AC-02.5: GIVEN the alert is displayed, WHEN the permission check runs, THEN it uses the actual voice memo directory path (`~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/`) expanded via `FileManager` — not a hardcoded user-specific path or a proxy directory.

### US-03: Normal launch when Full Disk Access is granted

As a user who has already granted Full Disk Access,
I want the app to launch normally with no interruption,
So that I am not bothered by permission prompts on every launch.

- [ ] AC-03.1: GIVEN Full Disk Access has been granted in System Settings, WHEN the app launches, THEN the main UI appears with no permission alert shown.

### US-04: Permission check logic is verified by automated tests

As a developer maintaining this app,
I want the permission-check model to have automated tests,
So that regressions (e.g., flipped boolean, wrong path) are caught before they ship.

- [ ] AC-04.1: GIVEN a test double where the voice memo directory is readable, WHEN the permission-check model initializes, THEN it reports access is available.
- [ ] AC-04.2: GIVEN a test double where the voice memo directory is NOT readable, WHEN the permission-check model initializes, THEN it reports access is unavailable.
- [ ] AC-04.3: GIVEN a test double that records which URLs it is called with, WHEN the permission-check model initializes, THEN the readability check was called with a URL whose path ends in `Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`.

---

## Edge Cases

| # | Scenario | Expected Behavior |
|---|----------|-------------------|
| E1 | Voice memo directory does not exist at all (user never opened Voice Memos, or iCloud not configured) | Treated the same as "not readable" — the alert is shown. The alert message covers both cases (it says "access" not "permission"). |
| E2 | Directory exists but is not readable for a reason other than Full Disk Access (e.g., ACL, filesystem error) | Same behavior — alert is shown. Full Disk Access is the overwhelmingly likely cause; diagnosing other filesystem issues is out of scope. |
| E3 | `x-apple.systempreferences` URL fails to open on a future macOS version | The app should still terminate after attempting to open the URL. The user can manually navigate to System Settings. Failure to open the URL must not leave the app running in a broken state. |
| E4 | User grants Full Disk Access but does not relaunch | Out of scope — the app does not detect runtime permission changes. The alert message instructs the user to relaunch. |
| E5 | Home directory is in a non-standard location | The path must be expanded using `FileManager.default.homeDirectoryForCurrentUser`, not a hardcoded `/Users/<name>/` prefix. |

---

## Success Criteria

- After this change ships, zero cases of the app silently failing to watch voice memos due to a missing Full Disk Access grant — every launch without the permission results in the blocking alert.
- The build verification command (`xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build test`) passes after all changes.

---

## Out of Scope (Clarification)

- **`MenuBarExtra` scene migration**: Raised because sandbox removal may interact with scene configuration, but this is unrelated work tracked separately. The permission gate will work with both `WindowGroup` and `MenuBarExtra` scenes.
- **Runtime permission re-detection**: Deliberately excluded to keep the implementation simple. The alert instructs the user to relaunch. Adding `applicationDidBecomeActive` monitoring would add complexity for minimal UX gain.

---

## Open Questions

- [x] **Should the app auto-detect permission grants without relaunch?**
  - Context: The app could monitor `applicationDidBecomeActive` to re-check permissions when the user returns from System Settings, avoiding a relaunch.
  - Options considered: (1) Auto-detect on activate — more polished UX but adds state management complexity. (2) Require relaunch — simpler, and this is a one-time setup step.
  - Decision needed by: 2026-03-28 (plan creation)
  - Decision: No — user must relaunch after granting Full Disk Access.
  - Reasoning: Simplifies implementation significantly. The alert instructs the user to relaunch. Auto-detection adds complexity for a one-time setup step.

- [x] **Should the plan cover disabling the sandbox?**
  - Context: The app sandbox is currently enabled in entitlements. Disabling it is a prerequisite for accessing the voice memo directory, but could be treated as a separate change.
  - Options considered: (1) Separate PR for sandbox removal. (2) Bundle sandbox removal with the permission gate in one plan.
  - Decision needed by: 2026-03-28 (plan creation)
  - Decision: Yes — removing `com.apple.security.app-sandbox` from entitlements is in scope.
  - Reasoning: The sandbox must be disabled for the app to access the voice memo directory at all. Both changes are required together and are meaningless in isolation.

---

## Assumptions

- The voice memo directory path `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/` is stable across the supported macOS range (15+).
- A failed readability check on the voice memo directory is a reliable indicator that Full Disk Access has not been granted (the overwhelmingly common cause for this specific path).
- The `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` URL scheme is stable across macOS 15+.
- `com.apple.security.network.client` remains valid outside the sandbox and does not need to be removed.

---

## Dependencies

- `spec.md` — documents the voice memo directory path and disk access requirement
- `Utterd/Resources/Utterd.entitlements` — sandbox configuration to modify
- `Utterd/App/UtterdApp.swift` — app entry point where the check will live
- `Libraries/Sources/Core/FileSystemChecker.swift` — existing protocol for filesystem abstraction (may be reused or paralleled in app target for testability)

---

## Testing Notes

**Automated tests:**
- The permission-check model should accept a filesystem-checking dependency (matching the project's established pattern with `FileSystemChecker` / `MockFileSystemChecker`). Three unit tests: two verify the boolean output for readable and not-readable states (AC-04.1, AC-04.2), and one verifies the model checks the correct directory path (AC-04.3) using a test double that records which URLs it was called with.

**Manual test matrix (AC-01 through AC-03):**

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Build the app | `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build test` passes | |
| 2 | Run `codesign -d --entitlements - /path/to/Utterd.app` | `com.apple.security.app-sandbox` is absent | |
| 3 | Revoke Full Disk Access for Utterd in System Settings, launch app | Alert appears within 1 second, main UI is not visible behind it | |
| 4 | Press Escape on the alert | Alert is not dismissed / app terminates | |
| 5 | Relaunch, click "Open System Settings" | System Settings opens to Full Disk Access pane, app quits | |
| 6 | Relaunch, click "Quit" | App terminates immediately | |
| 7 | Grant Full Disk Access, relaunch | App launches normally, no alert | |
| 8 | (E3) Temporarily change the URL scheme to an invalid value, click "Open System Settings" | App still terminates even though URL failed to open | |

**Build verification command:** `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build test`
