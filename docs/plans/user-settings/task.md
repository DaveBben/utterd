# User Settings & Configurable Pipeline — Task Breakdown

**Plan**: docs/plans/user-settings/plan.md
**Date**: 2026-04-02
**Status**: Approved

---

## Key Decisions

- **Settings storage**: `@Observable` class wrapping `UserDefaults` directly (not `@AppStorage`, which only works inside SwiftUI views). The class reads from `UserDefaults` in `init()` and writes in property `didSet` observers. The `@Observable` macro preserves `willSet`/`didSet` per SE-0395, but if `didSet` doesn't fire under the macro (edge case in some compiler versions), fall back to computed properties with explicit `withMutation(keyPath:)` calls. The Task 2 persistence tests (set → re-init → read) will catch any `didSet` failure at RED time. Alternative (`@AppStorage` in views) rejected because it scatters persistence across views and prevents unit testing.

- **Settings model location**: `Utterd/Core/UserSettings.swift` — app layer, not the Core library. The Core library (`Libraries/Sources/Core/`) should not depend on `UserDefaults` or Foundation's persistence APIs. Settings values are passed to Core components via the `RoutingConfiguration` value type. Alternative (settings in Core) rejected because it would couple the library to `UserDefaults`.

- **Dynamic config injection**: `NoteRoutingPipelineStage` accepts a `@Sendable () -> RoutingConfiguration` closure that replaces the current `mode: RoutingMode` init parameter. This closure is called at the start of each `route()` invocation, so settings changes take effect on the next memo without restarting the pipeline. AppDelegate creates this closure to read from `UserDefaults` (thread-safe, no MainActor needed). Alternative (restart pipeline on settings change) rejected as unnecessarily disruptive.

- **Default folder storage**: Store the folder *name* (`String`) in `UserDefaults`, not the folder ID. At routing time, resolve the name against the current top-level folder list. If the stored name no longer matches any folder, fall back to the system default (`nil`). Name-based matching handles the case where a folder is deleted and recreated (same name, new ID). Alternative (store folder ID) rejected because Apple Notes folder IDs are opaque and may be fragile across reinstalls.

- **Custom prompt `{notes_folders}` replacement**: Performed inside `TranscriptClassifier.classify()` when a `customSystemPrompt` parameter is provided. The replacement injects top-level folder names only (not nested hierarchy paths) as a dash-prefixed, newline-separated list, per AC-05.4. This differs from the built-in prompt which uses full hierarchy paths — custom prompts are simpler by design.

- **Timestamp update mechanism**: AppDelegate wraps the routing stage's `onComplete` callback to also update `AppState.lastProcessedDate` inside `MainActor.run`. This avoids adding callback plumbing to `PipelineController` or `NoteRoutingPipelineStage`. On app startup, the initial value is loaded from the store via `mostRecentlyProcessed()`. Alternative (periodic polling) rejected as unnecessarily complex when we already have the callback.

- **Folder picker model extraction**: The settings routing section uses a `SettingsRoutingModel` (`@Observable @MainActor`) that encapsulates folder fetching, error handling, and stale-selection detection. This keeps the view declarative and enables unit testing of the fetch/error logic with `MockNotesService`. Alternative (inline in view) rejected for lack of testability.

- **Settings window opening**: Use `Button` + `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` instead of `SettingsLink` to open the Settings window from the menu bar. `SettingsLink` is broken inside menu-style `MenuBarExtra` for `LSUIElement` apps (no main menu bar, no active SwiftUI render tree to find the `openSettings` action). The `sendAction` workaround is widely used by macOS menu bar apps and is stable on macOS 14+. Follow with `NSApp.activate()` to bring the settings window to front.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-01.1: No memos processed → "No memos processed yet" | Task 3 |
| AC-01.2: Processed memos → relative timestamp | Task 3 |
| AC-01.3: New memo processed → timestamp updates | Task 3 |
| AC-02.1: Settings button opens settings window | Task 4 |
| AC-02.2: Settings already open → bring to front | Task 4 |
| AC-03.1: Dropdown shows top-level folders | Task 4 |
| AC-03.2: Folder selection persisted immediately | Task 2, Task 4 |
| AC-03.3: Selection survives restart | Task 2 |
| AC-03.4: LLM disabled → memo routed to selected folder | Task 6 |
| AC-03.5: Deleted folder → revert to system default | Task 4 |
| AC-03.6: Folder fetch fails → inline error | Task 4 |
| AC-04.1: Fresh install → LLM toggle off | Task 2 |
| AC-04.2: LLM disabled → skip classification, default folder, fallback title | Task 6 |
| AC-04.3: LLM enabled, auto-route → built-in prompt | Task 6 |
| AC-04.4: LLM enabled, custom prompt → custom prompt with replacement | Task 6 |
| AC-04.5: macOS 15–25 → LLM toggle disabled | Task 5 |
| AC-05.1: Auto-route → built-in prompt, no editable text | Task 5 |
| AC-05.2: Custom prompt → text area with default pre-filled | Task 5 |
| AC-05.3: Custom prompt edited → persisted immediately | Task 2, Task 5 |
| AC-05.4: `{notes_folders}` replaced at processing time | Task 6 |
| AC-05.5: Unrecognized folder → user-configured default | Task 6 |
| AC-05.6: No `{notes_folders}` → prompt sent as-is | Task 6 |
| AC-05.7: Empty custom prompt → route to default without LLM | Task 6 |
| AC-06.1: Reset to Default restores template | Task 5 |
| AC-07.1: Fresh install → summarization off | Task 2 |
| AC-07.2: Summarization on → summarized body | Task 6 |
| AC-07.3: Summarization off → full transcript body | Task 6 |
| AC-07.4: LLM disabled → summarization toggle disabled | Task 5 |
| EC-01: Zero folders → default only | Task 6 |
| EC-02: Deleted default folder → system default | Task 4, Task 6 |
| EC-03: No `{notes_folders}` in custom prompt | Task 6 (AC-05.6) |
| EC-04: Empty custom prompt | Task 6 (AC-05.7) |
| EC-05: LLM toggled mid-classification | Task 6 (natural — config read per invocation) |
| EC-06: Folder fetch fails in settings | Task 4 (AC-03.6) |
| EC-07: Prompt exceeds context limits | Task 6 (existing `LLMContextBudget` handles) |
| EC-08: macOS 15–25, no LLM | Task 5 (AC-04.5) |
| `MemoStore.mostRecentlyProcessed` | Task 0, Task 1 |

---

## Tasks

### Task 0: Define Contracts & Interfaces

**Relevant Files:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` ← create
- `Libraries/Sources/Core/MemoStore.swift` ← modify (add protocol method)
- `Libraries/Sources/Core/TranscriptClassifier.swift` ← modify (add default prompt constant)

**Context to Read First:**
- `Libraries/Sources/Core/MemoStore.swift` — existing protocol to extend with `mostRecentlyProcessed()`
- `Libraries/Sources/Core/MemoRecord.swift` — `dateProcessed: Date?` field used by the new method
- `Libraries/Sources/Core/RoutingMode.swift` — existing enum; understand its relationship with the new `RoutingConfiguration` (summarizationEnabled maps to this)
- `Libraries/Sources/Core/TranscriptClassifier.swift` — existing `buildSystemPrompt()` format; derive the default custom prompt template from it, substituting the dynamic folder list with `{notes_folders}`

**Steps:**

1. [ ] Create `Libraries/Sources/Core/RoutingConfiguration.swift`:
   - Define `public struct RoutingConfiguration: Sendable, Equatable`
   - Nest `public enum LLMApproach: Sendable, Equatable` with cases `.disabled`, `.autoRoute`, `.customPrompt(String)`
   - Properties: `llmApproach: LLMApproach`, `defaultFolderName: String?`, `summarizationEnabled: Bool`
   - Memberwise `public init` with defaults: `.disabled`, `nil`, `false`
2. [ ] Add `func mostRecentlyProcessed() async -> MemoRecord?` to the `MemoStore` protocol in `Libraries/Sources/Core/MemoStore.swift`
3. [ ] Add `public static let defaultCustomPrompt: String` to `TranscriptClassifier` — mirror the structure of the existing `buildSystemPrompt()` but replace the dynamically-built folder list with the literal text `{notes_folders}`. Keep the examples and formatting intact.
4. [ ] Verify the package compiles: `cd Libraries && swift build </dev/null`

**Acceptance Criteria:**

- GIVEN the `RoutingConfiguration` struct, WHEN compiled, THEN all cases of `LLMApproach` are available and the struct conforms to `Sendable` and `Equatable`
- GIVEN the `MemoStore` protocol, WHEN a type conforms to it, THEN `mostRecentlyProcessed() async -> MemoRecord?` is a required method
- GIVEN `TranscriptClassifier.defaultCustomPrompt`, WHEN read, THEN it contains the literal string `{notes_folders}` and otherwise matches the structure of the built-in prompt (instructions, folder placeholder, examples)

**Do NOT:**
- Implement `mostRecentlyProcessed()` in `JSONMemoStore` or `MockMemoStore` — that is Task 1
- Add a `customSystemPrompt` parameter to `classify()` — that is Task 6
- Create any UI types or settings models — those are Tasks 2–5

---

### Task 1: MemoStore `mostRecentlyProcessed` Implementation

**Relevant Files:**
- `Libraries/Sources/Core/JSONMemoStore.swift` ← modify
- `Libraries/Tests/CoreTests/Mocks/MockMemoStore.swift` ← modify
- `Libraries/Tests/CoreTests/JSONMemoStoreTests.swift` ← modify

**Context to Read First:**
- `Libraries/Sources/Core/MemoStore.swift` — protocol with new `mostRecentlyProcessed()` from Task 0
- `Libraries/Sources/Core/JSONMemoStore.swift` — existing actor; understand the `records` array and the `oldestUnprocessed()` pattern (filter + min); the new method is the inverse (filter for processed + max)
- `Libraries/Sources/Core/MemoRecord.swift` — `dateProcessed: Date?` field; nil means unprocessed
- `Libraries/Tests/CoreTests/JSONMemoStoreTests.swift` — existing test structure and file helpers (temp directory, `insert`, `markProcessed`)

**Steps:**

1. [ ] Write failing tests in `JSONMemoStoreTests.swift`:
   - Test: empty store → returns nil
   - Test: all records unprocessed (dateProcessed == nil) → returns nil
   - Test: one processed record → returns that record
   - Test: multiple processed records with different dateProcessed values → returns the one with the latest dateProcessed
   - Test: mix of processed and unprocessed records → returns the most recently processed, ignoring unprocessed ones
2. [ ] Run tests to verify they fail: `cd Libraries && timeout 120 swift test </dev/null 2>&1`
3. [ ] Implement `mostRecentlyProcessed()` in both stores:
   - `JSONMemoStore`: filter `records` where `dateProcessed != nil`, return the element with `max(by:)` comparing `dateProcessed!` values. Return nil if the filtered set is empty.
   - `MockMemoStore`: add `var mostRecentlyProcessedResult: MemoRecord?` property (matching the existing `oldestUnprocessedResult` pattern — direct property, no setter method needed) and `var mostRecentlyProcessedCallCount: Int = 0` for call tracking; increment the counter on each call and return the stored result.
4. [ ] Run tests to verify they pass: `cd Libraries && timeout 120 swift test </dev/null 2>&1`

**Acceptance Criteria:**

- GIVEN an empty store, WHEN `mostRecentlyProcessed()` is called, THEN it returns `nil`
- GIVEN a store with only unprocessed records (`dateProcessed == nil`), WHEN `mostRecentlyProcessed()` is called, THEN it returns `nil`
- GIVEN a store with records processed at 10:00, 11:00, and 12:00, WHEN `mostRecentlyProcessed()` is called, THEN it returns the record with `dateProcessed` at 12:00
- GIVEN a store with a mix of processed and unprocessed records, WHEN `mostRecentlyProcessed()` is called, THEN it returns the most recently processed record, ignoring unprocessed ones

**Do NOT:**
- Modify the `MemoStore` protocol — that was done in Task 0
- Add any new persistence mechanism — use the existing in-memory `records` array
- Touch `PipelineController`, `AppDelegate`, or UI code — the store method is wired in Task 3

---

### Task 2: UserSettings Model with Persistence

**Relevant Files:**
- `Utterd/Core/UserSettings.swift` ← create
- `UtterdTests/UserSettingsTests.swift` ← create

**Context to Read First:**
- `Utterd/Core/AppState.swift` — existing `@Observable @MainActor final class` pattern to follow
- `Libraries/Sources/Core/RoutingConfiguration.swift` — `RoutingConfiguration` and `LLMApproach` types from Task 0; `UserSettings` will construct this via a `toRoutingConfiguration()` method
- `Libraries/Sources/Core/TranscriptClassifier.swift` — `defaultCustomPrompt` constant from Task 0; used as the initial/default value for the custom prompt property
- `spec.md` lines 86–104 — code conventions for `@Observable` models

**Steps:**

1. [ ] Write failing tests in `UtterdTests/UserSettingsTests.swift` (each test should create its own `UserDefaults(suiteName: "test-\(UUID().uuidString)")` for isolation and call `defaults.removePersistentDomain(forName:)` after):
   - Test: fresh `UserDefaults` suite → all properties have correct defaults (`llmEnabled` = false, `defaultFolderName` = nil, `useCustomPrompt` = false, `customPrompt` = `TranscriptClassifier.defaultCustomPrompt`, `summarizationEnabled` = false)
   - Test: set `llmEnabled` = true, create new `UserSettings` with same suite → reads true (survives re-init)
   - Test: set `defaultFolderName` = "Work", create new instance → reads "Work"
   - Test: set `useCustomPrompt` = true and `customPrompt` = "Custom text", create new instance → both persist
   - Test: `toRoutingConfiguration()` with LLM disabled → returns `.disabled` approach
   - Test: `toRoutingConfiguration()` with LLM enabled, `useCustomPrompt` = false → returns `.autoRoute`
   - Test: `toRoutingConfiguration()` with LLM enabled, `useCustomPrompt` = true, custom text → returns `.customPrompt("Custom text")`
   - Test: `toRoutingConfiguration()` correctly maps `summarizationEnabled` and `defaultFolderName`
2. [ ] Run tests to verify they fail: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`
3. [ ] Create `Utterd/Core/UserSettings.swift`:
   - Define `@Observable @MainActor final class UserSettings`
   - Accept `UserDefaults` suite in `init(defaults: UserDefaults = .standard)` for testability
   - Define nested `enum Keys` (internal access) with static string constants for each key: `llmEnabled`, `defaultFolderName`, `useCustomPrompt`, `customPrompt`, `summarizationEnabled`
   - Properties with `didSet` that writes to UserDefaults: `var llmEnabled: Bool`, `var defaultFolderName: String?`, `var useCustomPrompt: Bool`, `var customPrompt: String`, `var summarizationEnabled: Bool`. Note: if the persistence tests (step 1, "survives re-init") fail because `didSet` doesn't fire under the `@Observable` macro, switch to computed properties that read/write UserDefaults directly with manual `access(keyPath:)`/`withMutation(keyPath:)` calls for observation tracking
   - `init` reads each property from the provided `UserDefaults` instance, using `TranscriptClassifier.defaultCustomPrompt` as the default for `customPrompt` when no value is stored
   - `func toRoutingConfiguration() -> RoutingConfiguration`: if `!llmEnabled` → `.disabled`; if `useCustomPrompt` → `.customPrompt(customPrompt)`; else → `.autoRoute`. Pass through `defaultFolderName` and `summarizationEnabled`.
4. [ ] Run tests to verify they pass: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`

**Acceptance Criteria:**

- GIVEN a fresh `UserDefaults` suite with no stored values, WHEN `UserSettings` is initialized, THEN `llmEnabled` is `false`, `defaultFolderName` is `nil`, `useCustomPrompt` is `false`, `customPrompt` equals `TranscriptClassifier.defaultCustomPrompt`, `summarizationEnabled` is `false`
- GIVEN `llmEnabled` is set to `true`, WHEN a new `UserSettings` instance is created with the same suite, THEN `llmEnabled` reads as `true`
- GIVEN `defaultFolderName` is set to `"Work"`, WHEN a new instance reads from the same suite, THEN `defaultFolderName` is `"Work"`
- GIVEN LLM is disabled, WHEN `toRoutingConfiguration()` is called, THEN the result has `.disabled` LLM approach regardless of `useCustomPrompt`
- GIVEN LLM is enabled and `useCustomPrompt` is `true` with prompt `"My prompt"`, WHEN `toRoutingConfiguration()` is called, THEN the result has `.customPrompt("My prompt")` approach
- GIVEN LLM is enabled and `useCustomPrompt` is `false`, WHEN `toRoutingConfiguration()` is called, THEN the result has `.autoRoute` approach

**Do NOT:**
- Create any SwiftUI views — those are Tasks 4 and 5
- Touch `AppDelegate` or pipeline code — wiring is Task 6
- Use `@AppStorage` — it only works inside SwiftUI views; use `UserDefaults` directly in `didSet` / `init`

---

### Task 3: Menu Bar Last-Sync Timestamp Display

**Blocked By:** Task 1

**Relevant Files:**
- `Utterd/Core/AppState.swift` ← modify
- `Utterd/Features/MenuBar/MenuBarPopoverView.swift` ← modify (contains `MenuBarMenuContent`)
- `Utterd/Features/MenuBar/MenuBarStrings.swift` ← modify
- `Utterd/App/UtterdApp.swift` ← modify (pass appState to environment)
- `Utterd/App/AppDelegate.swift` ← modify (load initial timestamp + wrap onComplete)
- `UtterdTests/AppStateTests.swift` ← modify

**Context to Read First:**
- `Utterd/Core/AppState.swift` — add `lastProcessedDate: Date?` property to existing model
- `Utterd/Features/MenuBar/MenuBarPopoverView.swift` — current `MenuBarMenuContent` view with `Text(title)`, `Divider()`, quit button; extend with timestamp section
- `Utterd/Features/MenuBar/MenuBarStrings.swift` — existing string constants to extend
- `Utterd/App/UtterdApp.swift` — `MenuBarExtra` scene; need to pass `appState` into environment for `MenuBarMenuContent` to read
- `Utterd/App/AppDelegate.swift` — `startPipeline()` creates the store (line 86); `makePipelineController()` (lines 106–136) creates the routing stage via factory — wrap the `onComplete` callback to update `appState.lastProcessedDate`
- `Libraries/Sources/Core/MemoStore.swift` — `mostRecentlyProcessed()` protocol method from Task 0 for initial load

**Steps:**

1. [ ] Write failing tests in `AppStateTests.swift`:
   - Test: `lastProcessedDate` defaults to nil
   - Test: setting `lastProcessedDate` to a specific Date stores and returns that value
2. [ ] Run tests to verify they fail: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`
3. [ ] Add `var lastProcessedDate: Date? = nil` to `AppState`
4. [ ] Add string constants to `MenuBarStrings`: `static let lastSyncTitle = "Last Voice Memo Sync"`, `static let noMemosProcessed = "No memos processed yet"`
5. [ ] Update `MenuBarMenuContent`:
   - Add `@Environment(AppState.self) private var appState`
   - Replace the existing `Text(MenuBarStrings.title)` with a timestamp section: display `MenuBarStrings.lastSyncTitle` as a disabled label, then below it display either `MenuBarStrings.noMemosProcessed` (when `lastProcessedDate` is nil) or a relative timestamp using `Text(date, style: .relative)` (when non-nil), also as a disabled label
   - Keep the `Divider()` and quit button below the timestamp section
6. [ ] Update `UtterdApp.body`: add `.environment(appState)` to the `MenuBarMenuContent()` view inside the `MenuBarExtra` closure
7. [ ] Update `AppDelegate.startPipeline()`: after creating the `JSONMemoStore`, dispatch a Task that calls `await store.mostRecentlyProcessed()` and sets `self.appState?.lastProcessedDate = record?.dateProcessed` inside `MainActor.run`. Note: `record?.dateProcessed` is safe because `mostRecentlyProcessed()` only returns records where `dateProcessed != nil` (per Task 1's implementation), so the chained optional resolves correctly. If the store is empty or has no processed records, `record` is nil and `lastProcessedDate` stays nil (showing "No memos processed yet")
8. [ ] Update `AppDelegate.makePipelineController()`: in the `makeRoutingStage` factory closure, wrap the `onComplete` callback so that before calling the original `onComplete`, it executes `await MainActor.run { self?.appState?.lastProcessedDate = Date() }` (using `[weak self]` capture)
9. [ ] Run tests to verify they pass: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`

**Acceptance Criteria:**

- GIVEN no memos have been processed (`lastProcessedDate` is nil), WHEN `MenuBarMenuContent` renders, THEN it shows "Last Voice Memo Sync" and "No memos processed yet"
- GIVEN `lastProcessedDate` is set to a recent Date, WHEN `MenuBarMenuContent` renders, THEN it shows "Last Voice Memo Sync" and a relative timestamp (e.g., "2 minutes ago")
- GIVEN `AppState` is freshly created, WHEN `lastProcessedDate` is read, THEN it is nil
- GIVEN the app starts with processed memos in the store, WHEN the pipeline starts, THEN `appState.lastProcessedDate` is loaded from the store's most recently processed record
- GIVEN the routing stage completes processing a memo, WHEN `onComplete` fires, THEN `appState.lastProcessedDate` is updated to the current date

**Do NOT:**
- Add a Settings button to the menu bar — that is Task 4
- Modify any pipeline stage or Core library code — only wire the callback in AppDelegate
- Create any settings UI — those are Tasks 4 and 5
- Modify `MemoStore` protocol or implementations — that was done in Tasks 0 and 1

---

### Task 4: Settings Window — Routing Section & Menu Bar Integration

**Blocked By:** Task 2

**Relevant Files:**
- `Utterd/App/UtterdApp.swift` ← modify (add `Settings` scene)
- `Utterd/Features/MenuBar/MenuBarPopoverView.swift` ← modify (add Settings button)
- `Utterd/Features/Settings/SettingsView.swift` ← create
- `Utterd/Features/Settings/SettingsRoutingModel.swift` ← create
- `UtterdTests/SettingsRoutingModelTests.swift` ← create

**Context to Read First:**
- `Utterd/App/UtterdApp.swift` — current `@main` App struct with `MenuBarExtra` scene; add `Settings` scene alongside it
- `Utterd/Features/MenuBar/MenuBarPopoverView.swift` — `MenuBarMenuContent` view; add Settings button before the quit button
- `Utterd/Core/UserSettings.swift` — settings model from Task 2; bound to the folder dropdown via `settings.defaultFolderName`
- `Libraries/Sources/Core/NotesService.swift` — `listFolders(in:)` protocol method; call with `nil` for top-level folders
- `Libraries/Sources/Core/NotesFolder.swift` — `NotesFolder` struct with `id: String` and `name: String`
- `Utterd/Core/AppleScriptNotesService.swift` — concrete `NotesService` implementation; stateless, safe to instantiate in the settings view

**Steps:**

1. [ ] Write failing tests in `UtterdTests/SettingsRoutingModelTests.swift`:
   - Test: `loadFolders()` with successful fetch → `folders` populated, `isLoading` false, `fetchError` nil
   - Test: `loadFolders()` with failed fetch → `folders` empty, `fetchError` non-nil, `isLoading` false
   - Test: `validateSelection()` when `settings.defaultFolderName` matches a fetched folder → selection unchanged
   - Test: `validateSelection()` when `settings.defaultFolderName` does NOT match any fetched folder → `defaultFolderName` reset to nil
2. [ ] Run tests to verify they fail: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`
3. [ ] Create `Utterd/Features/Settings/SettingsRoutingModel.swift`:
   - `@Observable @MainActor final class SettingsRoutingModel`
   - Properties: `var folders: [NotesFolder] = []`, `var isLoading = false`, `var fetchError: (any Error)?`
   - Init takes `notesService: any NotesService` and `settings: UserSettings`
   - `func loadFolders() async`: set `isLoading = true`, call `notesService.listFolders(in: nil)`, populate `folders` on success, set `fetchError` on failure, set `isLoading = false`, call `validateSelection()`
   - `private func validateSelection()`: if `settings.defaultFolderName` is not nil and not in `folders.map(\.name)`, set `settings.defaultFolderName = nil`
4. [ ] Create `Utterd/Features/Settings/SettingsView.swift`:
   - `struct SettingsView: View` receiving `UserSettings` via `@Environment`
   - Top-level `Form` with a "Routing" `Section`
   - `Picker` for default folder bound to `settings.defaultFolderName`: first option "System Default" (value: nil), then one option per folder from `model.folders` (value: folder.name)
   - When `model.fetchError != nil`, show inline `Text` with the error description styled as secondary/red
   - Call `model.loadFolders()` in `.task { }` modifier
   - Leave a placeholder comment for the LLM section (Task 5 fills it in)
5. [ ] Add `Settings` scene to `UtterdApp.body`:
   - Create `@State private var userSettings = UserSettings()` in `UtterdApp`
   - Add: `Settings { SettingsView().environment(userSettings) }`
6. [ ] Add Settings button to `MenuBarMenuContent` (in `MenuBarPopoverView.swift`):
   - Insert a `Button(MenuBarStrings.settingsButton)` after the timestamp section divider and before the quit button
   - In the button action: call `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` followed by `NSApp.activate()` to bring the settings window to front
   - Do NOT use `SettingsLink` — it is broken inside menu-style `MenuBarExtra` for `LSUIElement` apps (see Key Decisions)
7. [ ] Run tests to verify they pass: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`

**Acceptance Criteria:**

- GIVEN the menu bar menu is open, WHEN the user clicks "Settings...", THEN the macOS settings window opens
- GIVEN the settings window is already open, WHEN the user clicks "Settings..." again, THEN the existing window is brought to front (standard SwiftUI `Settings` scene behavior)
- GIVEN the settings window is open and folder fetch succeeds with folders "Ideas", "Work", "Personal", WHEN the Routing section renders, THEN the dropdown shows "System Default", "Ideas", "Work", "Personal"
- GIVEN the user selects "Work" from the dropdown, WHEN the selection changes, THEN `settings.defaultFolderName` is immediately set to `"Work"`
- GIVEN `settings.defaultFolderName` is `"OldFolder"` and that name is not in the fetched folder list, WHEN `loadFolders()` completes, THEN `defaultFolderName` is reset to `nil`
- GIVEN the folder fetch throws an error, WHEN the Routing section renders, THEN the dropdown shows only "System Default" and an inline error message is displayed

**Do NOT:**
- Add the LLM section — that is Task 5
- Wire settings to the pipeline — that is Task 6
- Modify `NotesService`, folder fetching, or Core library code — use existing `listFolders(in: nil)` as-is
- Create the `UserSettings` model — that was done in Task 2

---

### Task 5: Settings Window — LLM Section

**Blocked By:** Task 4

**Relevant Files:**
- `Utterd/Features/Settings/SettingsView.swift` ← modify (add LLM section below Routing)
- `UtterdTests/SettingsLLMSectionTests.swift` ← create

**Context to Read First:**
- `Utterd/Features/Settings/SettingsView.swift` — current settings view from Task 4 with Routing section; add LLM section below it
- `Utterd/Core/UserSettings.swift` — settings model from Task 2; properties: `llmEnabled`, `useCustomPrompt`, `customPrompt`, `summarizationEnabled`
- `Libraries/Sources/Core/TranscriptClassifier.swift` — `defaultCustomPrompt` constant from Task 0; used by Reset to Default button

**Steps:**

1. [ ] Write failing tests in `UtterdTests/SettingsLLMSectionTests.swift` that verify the model-layer contracts the LLM section depends on:
   - Test: setting `llmEnabled = false` then calling `toRoutingConfiguration()` → `.disabled` regardless of other settings (confirms LLM toggle disables everything)
   - Test: setting `customPrompt` to edited text, then setting it to `TranscriptClassifier.defaultCustomPrompt` → `customPrompt` equals default (confirms Reset to Default behavior)
   - Test: setting `summarizationEnabled = true` while `llmEnabled = false` → `toRoutingConfiguration()` still returns `.disabled` (confirms summarization requires LLM)
2. [ ] Run tests to verify they fail: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`
3. [ ] Add "LLM" `Section` to `SettingsView` below the Routing section:
   - `Toggle("Enable LLM Routing", isOn: $settings.llmEnabled)`:
     - If `#unavailable(macOS 26)`: disable the toggle (`.disabled(true)`) and show `Text("Requires macOS 26 or later")` styled as secondary text below it
   - When `settings.llmEnabled` is true, show:
     - `Picker` (segmented or radio style) for routing mode with two options:
       - "Auto-route" — sets `settings.useCustomPrompt = false`
       - "Custom prompt" — sets `settings.useCustomPrompt = true`
     - When `settings.useCustomPrompt` is true:
       - `TextEditor` bound to `$settings.customPrompt` with a reasonable min height
       - `Button("Reset to Default")` that sets `settings.customPrompt = TranscriptClassifier.defaultCustomPrompt`
     - `Toggle("Enable Summarization", isOn: $settings.summarizationEnabled)`
   - When `settings.llmEnabled` is false: hide the routing mode picker, custom prompt editor, and summarization toggle (not visible — matching AC-05.1's "no user-editable prompt text is visible")
4. [ ] Run tests to verify they pass: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' test`

**Acceptance Criteria:**

- GIVEN a fresh install (LLM disabled by default), WHEN the user opens settings, THEN the LLM toggle is off and routing mode picker, custom prompt editor, and summarization toggle are not visible
- GIVEN the app runs on macOS 15–25 (`#unavailable(macOS 26)` is true), WHEN the user opens settings, THEN the LLM toggle is disabled with explanatory text "Requires macOS 26 or later"
- GIVEN LLM is enabled, WHEN the user selects "Auto-route", THEN no custom prompt text area is visible
- GIVEN LLM is enabled, WHEN the user selects "Custom prompt", THEN a text area appears pre-filled with `TranscriptClassifier.defaultCustomPrompt` (containing `{notes_folders}`)
- GIVEN "Custom prompt" is selected and the prompt has been edited, WHEN the user clicks "Reset to Default", THEN the text area is replaced with `TranscriptClassifier.defaultCustomPrompt`
- GIVEN a fresh install, WHEN the user opens settings, THEN the summarization toggle is off
- GIVEN LLM is disabled, WHEN the user views settings, THEN the summarization toggle is not visible (hidden, not just disabled)

**Do NOT:**
- Implement `{notes_folders}` replacement logic — that happens at processing time in Task 6, not in the UI
- Wire settings to the pipeline — that is Task 6
- Modify `UserSettings` properties — those were defined in Task 2
- Create new settings properties — all needed properties exist from Task 2

---

### Task 6: Pipeline Integration — Dynamic Settings

**Blocked By:** Task 0

**Relevant Files:**
- `Libraries/Sources/Core/TranscriptClassifier.swift` ← modify (add `customSystemPrompt` parameter)
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` ← modify (accept config provider, handle LLM skip + default folder)
- `Libraries/Tests/CoreTests/TranscriptClassifierTests.swift` ← modify (add custom prompt tests)
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` ← modify (update existing + add new tests)
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` ← modify (ensure nil-key entries in `listFoldersByParent` for default folder resolution)
- `Utterd/App/AppDelegate.swift` ← modify (wire `UserSettings` → `RoutingConfiguration`)

**Context to Read First:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` — `RoutingConfiguration` and `LLMApproach` types from Task 0
- `Libraries/Sources/Core/TranscriptClassifier.swift` — existing `classify()` and private `buildSystemPrompt()` to extend; note the `parse()` method handles response parsing regardless of prompt source
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` — existing `route()` and private `routeCore()` to refactor; current init takes `mode: RoutingMode`; the private `FolderHierarchyCache` actor remains unchanged
- `Libraries/Sources/Core/FolderHierarchyBuilder.swift` — `FolderHierarchyEntry` struct with `path` and `folder` fields; `resolveDefaultFolder()` filters for top-level entries (path without `"."`) from the already-fetched hierarchy
- `Libraries/Sources/Core/DateFallbackTitle.swift` — `dateFallbackTitle(for:)` used when LLM is disabled
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` — existing tests with `makeStage()` helper and direct stage constructions; ALL must be updated from `mode:` to `configProvider:` parameter
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` — mock setup for `listFolders` responses; existing `listFoldersByParent` keyed by parent ID (nil key = top-level); some tests may need a nil key entry added for the default folder resolution path
- `Utterd/App/AppDelegate.swift` — `makePipelineController()` factory (lines 106–136); current init passes `mode: .routeOnly` on line 130 — this is replaced by `configProvider`; this closure may already have the `onComplete` wrapping from Task 3; preserve that while adding the `configProvider`
- `Utterd/Core/UserSettings.swift` — `Keys` enum from Task 2 for reading UserDefaults keys in the config provider closure

**Steps:**

1. [ ] Write failing tests:
   - In `TranscriptClassifierTests.swift`:
     - Test: `classify()` with `customSystemPrompt` containing `{notes_folders}` and hierarchy with top-level folders "Work" and "Personal" → the LLM receives a system prompt with `{notes_folders}` replaced by `"- Work\n- Personal"`
     - Test: `classify()` with `customSystemPrompt` NOT containing `{notes_folders}` → LLM receives the prompt string unchanged
     - Test: `classify()` without `customSystemPrompt` (nil) → existing built-in prompt behavior unchanged
   - In `NoteRoutingPipelineStageTests.swift`:
     - Test: config `.disabled` → LLM not called, summarizer not called, note created in system default folder (nil) with `dateFallbackTitle` and full transcript
     - Test: config `.disabled` with `defaultFolderName: "Work"` and mock returning "Work" folder from `listFolders(in: nil)` → note created in the "Work" `NotesFolder`
     - Test: config `.disabled` with `defaultFolderName: "Gone"` (not in mock folder list) → note created in system default (nil)
     - Test: config `.disabled` with `defaultFolderName: "Work"` and folder hierarchy fetch fails → note created in system default (nil) without throwing (error caught internally)
     - Test: config `.autoRoute` → existing classification behavior preserved (LLM called with built-in prompt, folder matched from hierarchy)
     - Test: config `.customPrompt("my prompt {notes_folders}")` → LLM called with custom system prompt (verify via mock)
     - Test: config `.customPrompt("")` (empty) → LLM not called, note created in default folder
     - Test: config with `summarizationEnabled: true` → long transcript uses `.routeAndSummarize` mode (summary as body)
     - Test: config with `summarizationEnabled: false` → long transcript uses `.routeOnly` mode (full transcript as body)
     - Test: LLM returns unrecognized folder with `defaultFolderName: "Work"` → note created in "Work" (not nil)
2. [ ] Run tests to verify they fail: `cd Libraries && timeout 120 swift test </dev/null 2>&1`
3. [ ] Modify `TranscriptClassifier.classify()`:
   - Add optional parameter `customSystemPrompt: String? = nil`
   - If `customSystemPrompt` is provided: filter hierarchy for top-level entries (path does not contain `"."`), format as `"- \(entry.folder.name)"` joined by newlines, replace `{notes_folders}` in the custom prompt with this list; use the result as the system prompt
   - If `customSystemPrompt` is nil: call existing `buildSystemPrompt(hierarchy:)` unchanged
   - Response parsing (`parse()`) is unchanged — works identically for both prompt sources
4. [ ] Modify `NoteRoutingPipelineStage.init()`:
   - Remove the `mode: RoutingMode` parameter
   - Add `configProvider: @escaping @Sendable () -> RoutingConfiguration` parameter
   - Store as `private let configProvider: @Sendable () -> RoutingConfiguration`
   - Remove `private let mode: RoutingMode`
5. [ ] Add `private func resolveDefaultFolder(_ name: String?, from hierarchy: [FolderHierarchyEntry]) -> NotesFolder?` to `NoteRoutingPipelineStage`:
   - If name is nil, return nil (system default)
   - Filter hierarchy for top-level entries (path does not contain `"."`), find the first whose `folder.name` matches `name`
   - Return the matched folder, or nil if not found
   - This reuses the already-fetched hierarchy instead of making a separate `listFolders(in: nil)` AppleScript call — avoids doubled AppleScript overhead per memo and keeps folder resolution consistent with the cached hierarchy
6. [ ] Refactor `routeCore()` in `NoteRoutingPipelineStage`:
   - Call `configProvider()` at the top to get current config
   - Derive `let mode: RoutingMode = config.summarizationEnabled ? .routeAndSummarize : .routeOnly`
   - For ALL paths (including `.disabled`): fetch the hierarchy via `folderCache.get()` first, then resolve `let defaultFolder = resolveDefaultFolder(config.defaultFolderName, from: hierarchy)`. If the hierarchy fetch fails, catch the error, log it, and use nil (system default) as the default folder.
   - Replace all `notesService.createNote(... in: nil)` calls with `in: defaultFolder`
   - For `.disabled` LLM approach: skip summarization and classification; create note directly with `dateFallbackTitle(for: now)` and full transcript in `defaultFolder`
   - For `.customPrompt(let prompt)`: if prompt is empty, skip LLM and route to `defaultFolder`; otherwise call `TranscriptClassifier.classify()` with `customSystemPrompt: prompt`
   - For `.autoRoute`: call `TranscriptClassifier.classify()` without `customSystemPrompt` (existing behavior)
   - For folder matching after classification: fall back to `defaultFolder` instead of nil when no hierarchy match is found
7. [ ] Update existing tests in `NoteRoutingPipelineStageTests.swift`:
   - Update the `makeStage()` helper: replace `mode: RoutingMode = .routeOnly` parameter with `config: RoutingConfiguration = RoutingConfiguration(llmApproach: .autoRoute)` parameter; pass `configProvider: { config }` to the stage init
   - Update all direct `NoteRoutingPipelineStage(...)` constructions: replace `mode: .routeOnly` with `configProvider: { RoutingConfiguration(llmApproach: .autoRoute) }` and `mode: .routeAndSummarize` with `configProvider: { RoutingConfiguration(llmApproach: .autoRoute, summarizationEnabled: true) }`
   - Ensure all `listFoldersByParent` mock setups include a `nil` key entry (needed by `buildFolderHierarchy`'s initial `listFolders(in: nil)` call, which all config paths now use including `.disabled`) — most already do
8. [ ] Update `AppDelegate.makePipelineController()`:
   - Build a `@Sendable` `configProvider` closure that reads from `UserDefaults.standard` using `UserSettings.Keys` constants, constructs a `RoutingConfiguration`, and returns it — this closure is thread-safe (no MainActor needed since `UserDefaults` reads are thread-safe)
   - Pass this `configProvider` to `NoteRoutingPipelineStage` init (replacing the old `mode:` parameter)
   - Preserve the `onComplete` wrapping from Task 3 (timestamp update)
9. [ ] Run tests to verify they pass: `cd Libraries && timeout 120 swift test </dev/null 2>&1`
10. [ ] Verify full build: `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build`

**Acceptance Criteria:**

- GIVEN `classify()` is called with `customSystemPrompt: "Route to:\n{notes_folders}"` and hierarchy has top-level folders "Work" and "Personal", WHEN the LLM receives the prompt, THEN the system prompt is `"Route to:\n- Work\n- Personal"` (folder names dash-prefixed, one per line)
- GIVEN `classify()` is called with `customSystemPrompt: "Just pick a folder"` (no `{notes_folders}`), WHEN the LLM receives the prompt, THEN the system prompt is `"Just pick a folder"` unchanged
- GIVEN `classify()` is called without `customSystemPrompt` (nil), WHEN classification runs, THEN the built-in prompt is used (existing behavior preserved)
- GIVEN config has `.disabled` LLM approach, WHEN `route()` is called with transcript "Buy groceries", THEN no LLM call is made, no summarizer call is made, and the note is created in the default folder with a date-based fallback title and "Buy groceries" as body
- GIVEN config has `.disabled` with `defaultFolderName: "Work"` and "Work" exists in top-level folders, WHEN `route()` is called, THEN the note is created in the "Work" `NotesFolder`
- GIVEN config has `.disabled` with `defaultFolderName: "OldFolder"` and "OldFolder" is not in top-level folders, WHEN `route()` is called, THEN the note is created in the system default folder (nil)
- GIVEN config has `.disabled` with `defaultFolderName: "Work"` and the hierarchy fetch fails (AppleScript error), WHEN `route()` is called, THEN the note is created in the system default folder (nil) without throwing — the error is caught and logged
- GIVEN config has `.autoRoute`, WHEN `route()` is called, THEN the existing classification flow runs with the built-in prompt
- GIVEN config has `.customPrompt("My prompt {notes_folders}")`, WHEN `route()` is called, THEN `TranscriptClassifier.classify()` is called with `customSystemPrompt: "My prompt {notes_folders}"`
- GIVEN config has `.customPrompt("")`, WHEN `route()` is called, THEN no LLM call is made and the note is routed to the default folder
- GIVEN config has `summarizationEnabled: true`, WHEN a long transcript (exceeding context budget) is processed, THEN the note body contains the summary (`.routeAndSummarize` mode)
- GIVEN config has `summarizationEnabled: false`, WHEN a long transcript is processed, THEN the note body contains the full transcript (`.routeOnly` mode)
- GIVEN the LLM returns an unrecognized folder path and `defaultFolderName` is "Work", WHEN routing completes, THEN the note is created in "Work" (not the system default)
- GIVEN all existing tests are updated to use `configProvider`, WHEN the full test suite runs, THEN all previously passing tests still pass

**Do NOT:**
- Modify `UserSettings` — that was done in Task 2
- Create or modify Settings UI — those are Tasks 4 and 5
- Add new fields to `MemoStore` or `MemoRecord` — those were done in Tasks 0 and 1
- Modify `PipelineController` — only `AppDelegate.makePipelineController()` factory and `NoteRoutingPipelineStage` are in scope for pipeline wiring changes
- Modify the `onComplete` wrapping for timestamp updates — preserve what Task 3 established
