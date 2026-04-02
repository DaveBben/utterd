# User Settings & Configurable Pipeline

- **Date**: 2026-04-02
- **Status**: Approved
- **Author**: Dave / Claude
- **Project Spec**: [spec.md](../../../spec.md)

---

## What We Are Building

A settings system that gives users control over how voice memos are routed into Apple Notes, plus menu bar visibility into processing status.

The menu bar shows when the last voice memo was successfully routed (or "No memos processed yet" on first launch), followed by a "Settings" button that opens a standard macOS preferences window. The settings window has two sections: Routing (default folder selection) and LLM (enable/disable toggle, routing mode choice, summarization toggle). When LLM is disabled, memos skip classification and go directly to the user-selected default folder. When LLM is enabled, the user chooses between automatic folder-name routing or a custom prompt with a `{notes_folders}` template variable that is replaced at runtime.

---

## Why This Exists

Today the app has no user-facing configuration. The LLM always runs, it uses a hardcoded prompt, and there is no way to choose where memos go if the LLM is unavailable or unwanted. The user has no visibility into whether the system is working — there is no indication of when the last memo was processed. A user who wants simple voice-memo-to-notes without AI involvement cannot opt out, and a user who wants to customize routing behavior has no way to do so.

---

## Scope

### In

- Menu bar: last-sync timestamp display with "No memos processed yet" initial state
- Menu bar: "Settings" button that opens the settings window
- Settings window with Routing and LLM sections (immediate-apply, standard macOS pattern)
- Default folder selection dropdown (top-level Apple Notes folders)
- LLM enable/disable toggle (off by default on fresh install)
- Routing mode radio: Option A (auto-route) vs Option B (custom prompt)
- `{notes_folders}` template variable replacement in custom prompts
- "Reset to Default" button for custom prompt
- Summarization enable/disable toggle (off by default on fresh install)
- Settings persistence across app restarts
- Pipeline integration: skip LLM when disabled, respect routing mode and default folder
- `MemoStore` protocol extension for most-recently-processed record retrieval

### Out (explicitly)

- Nested/subfolder routing — only top-level folders for V1
- Remote LLM provider configuration
- Per-memo routing overrides or manual re-routing
- Notification system for processing events
- Settings import/export
- Onboarding wizard or first-run tutorial

---

## Technical Context

- **Platform**: macOS 15+ (Sequoia), on-device LLM requires macOS 26+
- **UI framework**: SwiftUI with `@Observable` pattern. The app currently uses a single `MenuBarExtra` scene with no settings window. SwiftUI's `Settings` scene is the standard macOS mechanism for preferences windows.
- **Persistence**: `UserDefaults` via `@AppStorage` for settings (standard macOS single-user app pattern)
- **Existing pipeline**: `PipelineController` → `TranscriptionPipelineStage` → `NoteRoutingPipelineStage`. The routing stage already accepts `RoutingMode` (.routeOnly / .routeAndSummarize) and uses `TranscriptClassifier` for LLM prompts.
- **Folder fetching**: `buildFolderHierarchy()` walks all folders via AppleScript, cached 5 min in `FolderHierarchyCache`. For settings, we only need top-level folders (`NotesService.listFolders(in: nil)`).
- **Menu bar**: `MenuBarExtra` in `UtterdApp.swift` with `MenuBarMenuContent` view.
- **Existing types**: `RoutingMode`, `TranscriptClassifier.classify(...)` (public entry point; the internal prompt builder is private), `NoteRoutingPipelineStage`, `LLMContextBudget`, `dateFallbackTitle(for:)`.
- **Folder caching**: `FolderHierarchyCache` is a private actor inside `NoteRoutingPipelineStage` — not reusable from settings. Settings will need its own folder-fetch call or the cache will need to be extracted.
- **Data store**: `JSONMemoStore` (actor) persists `MemoRecord` with `dateProcessed` field. Currently has `oldestUnprocessed()` but no method for most-recently-processed — this must be added as part of this work.

---

## User Stories

### US-01: View last sync status

**As a** user glancing at the menu bar,
**I want to** see when the last voice memo was successfully routed,
**so that** I know the system is working without opening any windows.

**Acceptance Criteria:**
- [ ] AC-01.1: GIVEN no memos have been processed, WHEN the menu bar menu is opened, THEN it displays "Last Voice Memo Sync" as a title and "No memos processed yet" as a subtitle
- [ ] AC-01.2: GIVEN one or more memos have been processed, WHEN the menu bar menu is opened, THEN it displays "Last Voice Memo Sync" as a title and the date/time of the most recently processed memo formatted as a localized relative timestamp (e.g., "2 minutes ago", "Yesterday at 3:45 PM") as a subtitle
- [ ] AC-01.3: GIVEN a new memo finishes processing while the app is running, WHEN the menu bar menu is opened, THEN the timestamp reflects the newly processed memo

### US-02: Open settings from menu bar

**As a** user who wants to configure the app,
**I want to** click "Settings" in the menu bar dropdown,
**so that** I can access all configuration options.

**Acceptance Criteria:**
- [ ] AC-02.1: GIVEN the menu bar menu is open, WHEN the user clicks "Settings", THEN the settings window opens
- [ ] AC-02.2: GIVEN the settings window is already open, WHEN the user clicks "Settings" again, THEN the existing window is brought to front

### US-03: Choose default routing folder

**As a** user,
**I want to** select which Apple Notes folder receives my voice memos by default,
**so that** memos go where I want them even without LLM routing.

**Acceptance Criteria:**
- [ ] AC-03.1: GIVEN the settings window is open, WHEN the user views the Routing section, THEN a dropdown shows all top-level Apple Notes folders
- [ ] AC-03.2: GIVEN the settings window is open, WHEN the user selects a different folder from the dropdown, THEN the selection is persisted immediately
- [ ] AC-03.3: GIVEN the user has selected "Work" as the default folder, WHEN the app quits and relaunches, THEN "Work" is still selected in the dropdown
- [ ] AC-03.4: GIVEN the user has selected "Work" as the default folder and LLM is disabled, WHEN the next voice memo is processed, THEN the note is created in "Work"
- [ ] AC-03.5: GIVEN the previously selected folder no longer exists in Apple Notes, WHEN the dropdown is opened, THEN the selection reverts to the system default Notes folder
- [ ] AC-03.6: GIVEN the settings window is open, WHEN fetching top-level folders fails (AppleScript error), THEN the dropdown shows only the currently persisted selection (or system default if none persisted) and an inline error message is displayed in the Routing section

### US-04: Enable/disable LLM routing

**As a** user,
**I want to** toggle LLM-powered routing on or off,
**so that** I control whether AI is involved in organizing my memos.

**Acceptance Criteria:**
- [ ] AC-04.1: GIVEN a fresh install, WHEN the user opens settings, THEN the LLM toggle is off
- [ ] AC-04.2: GIVEN LLM is disabled and the user has configured "Work" as the default routing folder, WHEN a voice memo is processed, THEN it skips classification entirely and creates a note in the "Work" folder with the full transcript as the note body and a date-based fallback title
- [ ] AC-04.3: GIVEN LLM is enabled and Option A (auto-route) is selected, WHEN a voice memo is processed, THEN the memo is classified using the built-in prompt with current top-level folder names, and the note is created in the matched folder (or the user-configured default folder if no match)
- [ ] AC-04.4: GIVEN LLM is enabled and Option B (custom prompt) is selected, WHEN a voice memo is processed, THEN the memo is classified using the user's custom prompt (with `{notes_folders}` replaced), and the note is created in the matched folder (or the user-configured default folder if no match)
- [ ] AC-04.5: GIVEN the app is running on macOS 15–25, WHEN the user opens settings, THEN the LLM enable toggle is disabled with an explanation that macOS 26+ is required

### US-05: Choose routing mode (auto vs custom)

**As a** user with LLM enabled,
**I want to** choose between automatic folder-name routing and a custom prompt,
**so that** I get the right level of control over how memos are classified.

**Acceptance Criteria:**
- [ ] AC-05.1: GIVEN LLM is enabled, WHEN the user selects Option A (auto-route), THEN the app uses a built-in classification prompt that automatically includes the current top-level folder names, and no user-editable prompt text is visible in settings
- [ ] AC-05.2: GIVEN LLM is enabled, WHEN the user selects Option B (custom prompt), THEN a text area appears with the default prompt pre-filled (including `{notes_folders}` placeholder)
- [ ] AC-05.3: GIVEN Option B is selected, WHEN the user edits the prompt, THEN the custom prompt is persisted immediately
- [ ] AC-05.4: GIVEN Option B is selected, WHEN a memo is processed, THEN `{notes_folders}` in the prompt is replaced with a newline-separated list of current top-level folder names (one per line, dash-prefixed) at processing time, not at save time
- [ ] AC-05.5: GIVEN Option B is selected and the LLM returns an unrecognized folder, WHEN routing completes, THEN the memo is routed to the user-configured default folder
- [ ] AC-05.6: GIVEN Option B is selected and the custom prompt does not contain `{notes_folders}`, WHEN a memo is processed, THEN the prompt is sent as-is to the LLM without folder injection
- [ ] AC-05.7: GIVEN Option B is selected and the custom prompt is empty, WHEN a memo is processed, THEN it is routed to the default folder without calling the LLM

### US-06: Reset custom prompt to default

**As a** user who customized the prompt but wants to start over,
**I want to** click "Reset to Default",
**so that** the prompt returns to the built-in template.

**Acceptance Criteria:**
- [ ] AC-06.1: GIVEN Option B is selected and the prompt has been edited, WHEN the user clicks "Reset to Default", THEN the text area is replaced with the default prompt template (including `{notes_folders}`)

### US-07: Toggle summarization

**As a** user with LLM enabled,
**I want to** enable or disable transcript summarization,
**so that** I choose whether long memos are condensed or kept verbatim.

**Acceptance Criteria:**
- [ ] AC-07.1: GIVEN a fresh install, WHEN the user opens settings, THEN the summarization toggle is off
- [ ] AC-07.2: GIVEN LLM is enabled and summarization is on, WHEN a transcript exceeding the context budget word limit is processed, THEN the note body contains the summarized version rather than the full transcript
- [ ] AC-07.3: GIVEN LLM is enabled and summarization is off, WHEN a transcript exceeding the context budget word limit is processed, THEN the note body contains the full transcript
- [ ] AC-07.4: GIVEN LLM is disabled, WHEN the user views settings, THEN the summarization toggle is visually disabled (summarization requires LLM)

---

## Edge Cases

| # | Scenario | Expected Behavior |
|---|----------|-------------------|
| EC-01 | Apple Notes has zero top-level folders | Default folder dropdown shows only the system default Notes folder; Option A auto-route has no meaningful folders to route to — all memos go to default |
| EC-02 | Selected default folder is deleted from Apple Notes | Next time the dropdown is opened or a memo is routed, fall back to the system default Notes folder; update the persisted selection |
| EC-03 | Custom prompt (Option B) does not contain `{notes_folders}` | The prompt is sent as-is without folder injection (covered by AC-05.6) |
| EC-04 | Custom prompt is empty | Route to default folder without calling the LLM (covered by AC-05.7) |
| EC-05 | LLM is toggled off while a memo is mid-classification | The in-flight memo completes with LLM; the setting takes effect for the next memo |
| EC-06 | Folder list fetch fails when opening settings (AppleScript error) | Show the dropdown with only the current selection (or system default); display an inline error message (covered by AC-03.6) |
| EC-07 | `{notes_folders}` replacement produces a prompt exceeding context limits | The existing `LLMContextBudget` mechanism handles truncation; the user's custom instructions may be partially cut — acceptable for V1 |
| EC-08 | App is running on macOS 15–25 (no LLM available) | The LLM section is visible but the enable toggle is disabled with an explanation that macOS 26+ is required (covered by AC-04.4) |

---

## Success Criteria

| Metric | Target |
|--------|--------|
| Settings persist across app restarts | 100% of settings values survive quit + relaunch |
| LLM-disabled memos skip classification | 0 LLM calls when toggle is off |
| Default folder respected | Memos routed to the user-configured folder when LLM is off or LLM returns no match |
| `{notes_folders}` replacement works | Template variable is replaced with current folder names at processing time, not at save time |
| Menu bar timestamp updates | Timestamp reflects the most recently processed memo within one polling cycle (30s) |

---

## Dependencies & Assumptions

- **Dependency**: `MemoStore` protocol must be extended with a method to retrieve the most recently processed record (or most recent `dateProcessed` value). This affects the protocol, `JSONMemoStore`, and `MockMemoStore`. US-01 is blocked by this extension.
- **Terminology**: "User-configured default folder" = the folder the user selects in US-03 settings dropdown. "Notes system default folder" = whatever Apple Notes uses when `createNote(in: nil)` is called (typically "Notes"). Throughout this plan, "default folder" means the user-configured default folder. If the user has not configured one, it falls back to the Notes system default folder.
- **Dependency**: `NotesService.listFolders(in: nil)` returns top-level folders reliably (already implemented and tested)
- **Dependency**: `spec.md` — project spec for architecture conventions and testing strategy
- **Assumption**: `UserDefaults` / `@AppStorage` is appropriate for settings persistence (standard macOS single-user app pattern)
- **Assumption**: SwiftUI's `Settings` scene is the correct mechanism for the preferences window (standard macOS pattern; opened via the app menu or programmatically)
- **Assumption**: Top-level folder list is small enough that fetching it on settings open does not cause noticeable lag
- **Assumption**: The pipeline can read settings values dynamically (via `UserDefaults`) without requiring a restart

---

## Open Questions

- [x] Should LLM routing be on or off by default for new installs?
  - **Decision**: Off by default
  - **Reasoning**: User consent — memos should not be processed by AI without explicit opt-in

- [x] Should settings use Save/Cancel or immediate-apply?
  - **Decision**: Immediate-apply (standard macOS pattern)
  - **Reasoning**: Follows macOS Human Interface Guidelines; simpler implementation; no risk of lost changes

- [x] Should the default folder dropdown show top-level or nested folders?
  - **Decision**: Top-level only
  - **Reasoning**: Reduces complexity for V1; nested folder routing deferred

- [x] How should the LLM prompt handle changing folder names?
  - **Decision**: Template variable `{notes_folders}` replaced at runtime (processing time)
  - **Reasoning**: Ensures folder list is always current without requiring the user to manually update; custom prompts (Option B) use the same template variable so the user controls prompt structure while the app keeps folder names fresh

- [x] Should summarization default be on or off?
  - **Decision**: Off by default
  - **Reasoning**: Consistent with LLM-off default; summarization condenses content which could be unexpected if not explicitly opted into

- [x] What is the settings window structure and menu bar copy?
  - **Decision**: Two sections (Routing, LLM). Menu bar shows "Last Voice Memo Sync" title with timestamp subtitle. LLM routing mode presented as two radio options (Option A: auto-route, Option B: custom prompt with `{notes_folders}` template variable).
  - **Reasoning**: Specified by the user during interview; UI structure and copy were iteratively refined across multiple rounds of discussion

---

## Out of Scope (Clarification)

- **Nested folder routing**: Only top-level folders are used for V1. The LLM prompt includes only top-level folder names. Subfolder routing may be added later.
- **Remote LLM**: No configuration for API keys or remote providers. On-device Foundation Model only.
- **Migration**: No migration path from pre-settings behavior. Fresh installs start with LLM off; existing users will see LLM off after update (safe default).
- **Undo/history**: No way to re-route a memo after it has been processed. Out of scope.
