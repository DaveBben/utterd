# Menu Bar Icon — Task Breakdown

**Plan**: [plan.md](plan.md)
**Date**: 2026-03-30
**Status**: In Progress

---

## Key Decisions

- **MenuBarExtra over NSStatusItem**: SwiftUI `MenuBarExtra` with `.window` style for the popover — aligns with the project's "SwiftUI first" convention and the architecture decision in spec.md. NSStatusItem rejected for requiring AppKit boilerplate. The `.window` style supports arbitrary SwiftUI content (Text, Button, Divider, custom layouts) and has been stable since macOS 13.
- **LSUIElement via Info.plist**: Add `LSUIElement = true` to Info.plist to hide the Dock icon. This is the standard macOS mechanism for menu-bar-only apps. XcodeGen's `info.properties` in project.yml is the right place to declare it so it survives project regeneration. Note: with LSUIElement, the app does not appear in the Cmd+Tab switcher — AC-01.5's "Cmd-Tab" activation path is untriggerable; the meaningful test is "double-clicks the app in Finder."
- **Remove WindowGroup, keep Settings scene**: The plan requires "no window opens" on launch. Remove the `WindowGroup` scene entirely from `UtterdApp.swift`. The `Settings` scene remains alongside `MenuBarExtra`.
- **Cmd+, breaks with LSUIElement — accepted regression**: `LSUIElement = true` removes the app's menu bar, which means the `Settings` scene's automatic Cmd+, shortcut binding has no menu item to attach to. This is a known limitation of menu-bar-only apps (documented by Apple FB10184971). Since the plan explicitly defers wiring the "Settings..." button, Cmd+, access to Settings is a known regression that will be resolved in a future plan when the Settings button is wired. Note: `NSApp.sendAction(Selector(("showSettingsWindow:")))` may not work reliably on macOS Sequoia+; prefer `@Environment(\.openSettings)` with activation policy management or the `SettingsAccess` library pattern when the time comes. AC-04.3 is remapped to acknowledge this.
- **Popover strings as testable constants**: The user-facing popover strings ("Last Voice Memo Synced", "Yesterday, 1:25 AM", "Settings...", "Quit Utterd") are defined as static constants in a `MenuBarStrings` enum. The view reads from these constants. This makes the content testable and serves as documentation for future localization. Scene configuration values (menu bar label, icon name) are inlined in `UtterdApp.swift` since they are used once and are not user-facing text.
- **Conditional MenuBarExtra to prevent ghost icon**: SwiftUI evaluates `App.body` (registering scenes including `MenuBarExtra`) BEFORE `applicationDidFinishLaunching` fires on the `NSApplicationDelegateAdaptor`. This means the menu bar icon would appear before the permission alert blocks via `runModal()` — causing a "ghost icon" flash. To prevent this, `AppState` gains a `permissionResolved: Bool` flag (default `false`). The `MenuBarExtra` is conditionally included in the scene body only when `permissionResolved` is `true`. `AppDelegate` sets `appState.permissionResolved = true` after the permission gate passes (or after the alert flow completes). This keeps the state in the existing `AppState` class (already in the environment) and avoids making `AppDelegate` observable.
- **AppCommands.swift becomes orphaned**: With `LSUIElement = true`, the app has no application menu bar, so `AppCommands` (which replaces the "New Item" command and adds a "Refresh" shortcut) has no menu to attach to. The file is intentionally retained for future use — not deleted, just disconnected.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-01.1: Menu bar icon on launch, no window | Task 1 (LSUIElement), Task 3 (MenuBarExtra scene) |
| AC-01.2: No Dock icon | Task 1 (LSUIElement config) |
| AC-01.3: Permission alert before menu bar icon | Task 2 (conditional scene + permissionResolved flag) |
| AC-01.4: Quit on permission alert dismissal | Task 2, Task 4 (existing handleOpenSystemSettings) |
| AC-01.5: No window on re-activate | Task 3 (WindowGroup removed). Note: LSUIElement prevents Cmd+Tab activation; manual test via Finder double-click |
| AC-02.1: Popover with title and subtitle | Task 3 |
| AC-02.2: Toggle popover on icon click | Task 3 (native MenuBarExtra behavior) |
| AC-02.3: Dismiss popover on outside click | Task 3 (native MenuBarExtra behavior) |
| AC-02.4: Visual layout (manual check) | Task 3 |
| AC-03.1: Quit button terminates app | Task 3 |
| AC-04.1: Settings item visible | Task 3 |
| AC-04.2: Settings click is no-op | Task 3 |
| AC-04.3: Cmd+, opens Settings | Deferred — known regression from LSUIElement; see Key Decisions |
| Edge: Permission alert before menu bar | Task 2 (conditional MenuBarExtra prevents ghost icon) |
| Edge: MenuBarExtra init order vs permission | Task 2 (permissionResolved flag gates scene) |
| Success: Zero windows on launch | Task 3 |
| Success: Zero Dock icon | Task 1 |

---

## Tasks

### Task 0: Define Contracts & Shared Constants

**Relevant Files:**
- `Utterd/Features/MenuBar/MenuBarStrings.swift` <- create
- `UtterdTests/MenuBarStringsTests.swift` <- create

**Context to Read First:**
- `Utterd/Core/AppState.swift` — existing shared state pattern; this task will also add a `permissionResolved` property here
- `Utterd/App/AppDelegate.swift` — existing `PermissionGateAction` enum and `evaluatePermissionGate`/`handleOpenSystemSettings` functions are the stable interface boundary for Task 4; no changes to signatures needed
- `UtterdTests/AppStateTests.swift` — existing test pattern for AppState

**Steps:**

1. [x] Write failing tests in `UtterdTests/MenuBarStringsTests.swift` using `@Suite("MenuBarStrings")` and `@Test`: (a) `#expect(MenuBarStrings.title == "Last Voice Memo Synced")`, (b) `#expect(MenuBarStrings.subtitle == "Yesterday, 1:25 AM")`, (c) `#expect(MenuBarStrings.settingsButton == "Settings...")`, (d) `#expect(MenuBarStrings.quitButton == "Quit Utterd")`
2. [x] Run tests to verify they fail (confirm RED state — `MenuBarStrings` type does not yet exist)
3. [x] Create `Utterd/Features/MenuBar/MenuBarStrings.swift` with an enum `MenuBarStrings` containing static let constants for the four user-facing popover strings: `title`, `subtitle`, `settingsButton`, `quitButton`
4. [x] Add `var permissionResolved = false` property to `AppState` in `Utterd/Core/AppState.swift` — this flag will be used by Task 2 to conditionally show the `MenuBarExtra` scene
5. [x] Run tests to verify they pass (confirm GREEN state); then run `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build` to verify compilation

**Acceptance Criteria:**

- GIVEN the `MenuBarStrings` enum, WHEN unit tests run, THEN all four string constants match their expected values
- GIVEN `AppState`, WHEN initialized, THEN `permissionResolved` defaults to `false`
- GIVEN the contracts, WHEN compiled, THEN no type errors exist

**Do NOT:**
- Implement any view or scene logic — only define the shared constants and the state flag
- Add a model class — static constants are sufficient for this plan's static placeholders
- Modify `AppDelegate` — setting the flag is Task 2's responsibility

---

### Task 1: Configure App as Menu-Bar-Only Daemon

**Blocked By:** Task 0

**Relevant Files:**
- `project.yml` <- modify (add LSUIElement to info properties)
- `Utterd/Resources/Info.plist` <- verify after regeneration

**Context to Read First:**
- `project.yml` — current XcodeGen configuration; need to add `LSUIElement: true` under `info.properties`
- `Utterd/Resources/Info.plist` — current plist; verify it does NOT already have LSUIElement

**Steps:**

1. [x] Add `LSUIElement: true` to the `Utterd` target's `info.properties` in `project.yml`
2. [x] Run `xcodegen generate` to regenerate the Xcode project
3. [x] Verify the generated Info.plist contains `<key>LSUIElement</key><true/>` by reading the file — if the key is missing, the step fails
4. [x] Run `xcodebuild -scheme Utterd -destination 'platform=macOS' build` to verify the project compiles with the new setting

No TDD cycle — this is a configuration-only task verified by compilation and file inspection.

**Acceptance Criteria:**

- GIVEN the project.yml with LSUIElement added, WHEN `xcodegen generate` runs, THEN the generated Info.plist contains `<key>LSUIElement</key><true/>`
- GIVEN the built app, WHEN launched, THEN it does not appear in the macOS Dock (manual verification)

**Do NOT:**
- Remove the WindowGroup from UtterdApp.swift — that is Task 3
- Add any MenuBarExtra code — that is Task 3
- Modify AppDelegate — that is Task 2

---

### Task 2: Wire Permission Gate to Control MenuBarExtra Visibility

**Blocked By:** Task 0

**Relevant Files:**
- `Utterd/App/AppDelegate.swift` <- modify (set permissionResolved flag after gate passes)
- `UtterdTests/PermissionGateTests.swift` <- modify (add tests for flag-setting behavior)
- `UtterdTests/Mocks/MockFileSystemChecker.swift` <- read only

**Context to Read First:**
- `Utterd/App/AppDelegate.swift` — current permission gate; need to understand where to set `permissionResolved = true` after the gate completes
- `Utterd/Core/AppState.swift` — now has `permissionResolved` flag from Task 0; `AppDelegate` needs a reference to set it
- `UtterdTests/PermissionGateTests.swift` — existing tests to understand coverage and avoid duplication; `evaluatePermissionGate` access-granted and access-denied cases are already covered
- `UtterdTests/Mocks/MockFileSystemChecker.swift` — mock used by permission tests

**Steps:**

1. [x] Write failing tests: (a) a test verifying that `handleOpenSystemSettings` is called with a URL containing `"Privacy_AllFiles"` — use the injectable closure pattern: `handleOpenSystemSettings(openURL: { url in receivedURL = url; return true }, terminate: { })` and assert `receivedURL?.absoluteString.contains("Privacy_AllFiles") == true`. This tests the URL construction logic not currently covered. (b) A test verifying that after `evaluatePermissionGate` returns `.proceed`, the caller can set `permissionResolved = true` on an `AppState` instance (tests the contract, not the wiring — the wiring is in `applicationDidFinishLaunching` which is hard to unit-test)
2. [x] Run tests to verify they fail (confirm RED state)
3. [x] Modify `AppDelegate` to accept an `AppState` reference: add a `var appState: AppState?` property. In `applicationDidFinishLaunching`, after `evaluatePermissionGate` returns `.proceed`, set `appState?.permissionResolved = true`. If the gate shows the permission alert and the user grants access (opens System Settings), the app terminates anyway, so the flag is only set on the `.proceed` path.
4. [x] Add a comment in `applicationDidFinishLaunching` explaining the timing: `// SwiftUI evaluates App.body (including MenuBarExtra scenes) BEFORE applicationDidFinishLaunching fires. The MenuBarExtra is conditionally included only when permissionResolved is true, preventing a "ghost icon" from appearing before the permission check completes.`
5. [x] Run tests to verify they pass (confirm GREEN state); then run `xcodebuild -scheme Utterd -destination 'platform=macOS' test` to verify full suite passes

**Acceptance Criteria:**

- GIVEN `handleOpenSystemSettings` is called with injectable closures, WHEN executed, THEN the `openURL` closure receives a URL containing `"Privacy_AllFiles"` (automated test)
- GIVEN `evaluatePermissionGate` returns `.proceed`, WHEN `applicationDidFinishLaunching` completes, THEN `appState.permissionResolved` is `true`
- GIVEN `evaluatePermissionGate` returns `.showPermissionAlert`, WHEN the permission alert is shown, THEN `permissionResolved` remains `false` (the app terminates via the alert flow, never setting the flag)
- GIVEN all existing permission tests, WHEN the full test suite runs, THEN zero regressions

**Do NOT:**
- Rewrite the permission gate logic — only add the `permissionResolved` flag-setting
- Make `AppDelegate` observable — use a simple stored property reference to `AppState`
- Modify MenuBarStrings or any view code — those are other tasks
- Duplicate existing tests — `evaluatePermissionGate` access-granted/denied cases are already covered

---

### Task 3: Replace WindowGroup with Conditional MenuBarExtra Popover

**Blocked By:** Task 0, Task 1, Task 2

**Relevant Files:**
- `Utterd/Features/MenuBar/MenuBarPopoverView.swift` <- create
- `Utterd/App/UtterdApp.swift` <- modify (replace WindowGroup with conditional MenuBarExtra)

**Context to Read First:**
- `Utterd/Features/MenuBar/MenuBarStrings.swift` — string constants defined in Task 0; the view must reference these, not inline literals
- `Utterd/App/UtterdApp.swift` — current scene structure with WindowGroup and Settings; this is the file being transformed
- `Utterd/App/AppDelegate.swift` — now sets `appState.permissionResolved = true` after permission gate passes (Task 2); the `MenuBarExtra` must be conditional on this flag
- `Utterd/Core/AppState.swift` — has `permissionResolved` flag; must be passed to the conditional scene check
- `Utterd/App/ContentView.swift` — currently attached to the WindowGroup scene being removed; read to confirm no other scene dependency exists

**Steps:**

1. [ ] Create `Utterd/Features/MenuBar/MenuBarPopoverView.swift`: a SwiftUI `View` struct containing a `VStack(alignment: .leading, spacing: 8)` with: `Text(MenuBarStrings.title)` using `.font(.headline)`, `Text(MenuBarStrings.subtitle)` using `.font(.subheadline).foregroundStyle(.secondary)`, `Divider()`, `Button(MenuBarStrings.settingsButton) { }` (no-op), and `Button(MenuBarStrings.quitButton) { NSApplication.shared.terminate(nil) }`. Apply `.padding()` to the VStack and set `.frame(minWidth: 220)`.
2. [ ] Modify `Utterd/App/UtterdApp.swift`: remove the `WindowGroup` scene and its `.defaultSize` and `.commands { AppCommands() }` modifiers. Add a conditional `MenuBarExtra` that only appears when `appState.permissionResolved` is `true`: use `if appState.permissionResolved { MenuBarExtra("Utterd", systemImage: "waveform") { MenuBarPopoverView() }.menuBarExtraStyle(.window) }`. Keep the `Settings` scene with `.environment(appState)`. Keep `@NSApplicationDelegateAdaptor` and `@State private var appState`. Wire `appDelegate.appState = appState` in an `.onAppear` or initializer so the delegate can set the flag.
3. [ ] Run `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build` to verify compilation
4. [ ] Run `xcodebuild -scheme Utterd -destination 'platform=macOS' test` to verify the full test suite passes (no regressions from WindowGroup removal)

Note: This task has no dedicated unit tests because the view is pure static UI with no logic or branching. The `MenuBarStrings` constants are already tested in Task 0. The popover layout is verified by manual inspection (AC-02.4). The conditional scene behavior is verified by the `permissionResolved` tests in Task 2.

**Acceptance Criteria:**

- GIVEN the app is launched with Full Disk Access, WHEN `applicationDidFinishLaunching` sets `permissionResolved = true`, THEN a waveform icon (`systemImage: "waveform"`) appears in the macOS menu bar and no window opens
- GIVEN the app is launched without Full Disk Access, WHEN the permission alert is showing, THEN no menu bar icon is visible (the conditional `MenuBarExtra` is not included because `permissionResolved` is `false`)
- GIVEN the app is running, WHEN the user clicks the menu bar icon, THEN a popover appears showing "Last Voice Memo Synced" as primary text and "Yesterday, 1:25 AM" as secondary text below it, separated from action items by a divider (manual verification for layout)
- GIVEN the popover is open, WHEN the user views the action items, THEN "Settings..." appears as a clickable button and "Quit Utterd" appears below it
- GIVEN the popover is open, WHEN the user clicks "Settings...", THEN nothing happens (no window, no alert, no error log)
- GIVEN the popover is open, WHEN the user clicks "Quit Utterd", THEN the application terminates immediately with no confirmation dialog (verified by code review — `NSApplication.shared.terminate(nil)` is called inline)
- GIVEN the popover is open, WHEN the user clicks the menu bar icon again or clicks outside the popover, THEN the popover dismisses (native MenuBarExtra `.window` style behavior)
- GIVEN the app is running, WHEN the user double-clicks the app in Finder, THEN no window opens (WindowGroup has been removed)
- GIVEN the full test suite, WHEN all tests run, THEN zero failures

**Do NOT:**
- Wire the "Settings..." button to open the Settings window — it is an intentional no-op per plan scope
- Add any dynamic data or model class — static constants in `MenuBarStrings` are sufficient
- Delete `ContentView.swift`, `HomeView.swift`, `HomeModel.swift`, `SidebarView.swift`, or `AppCommands.swift` — these are existing code retained for future use; just disconnect from the scene
- Add `// TODO: AC-04.3` comment in `UtterdApp.swift` near the `MenuBarExtra` scene to mark the Cmd+, regression for future resolution

---
