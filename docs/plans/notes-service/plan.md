# Notes Service Interface Plan

**Date**: 2026-03-30
**Status**: Approved
**Author**: Claude (with Dave)
**Project Spec**: spec.md

---

## What We Are Building

A service that lets the app discover the user's Apple Notes folder structure and create notes in specific folders. The service hides the complexity of talking to Apple Notes so the rest of the app does not need to know how Notes is accessed. When a requested folder doesn't exist, the service falls back to the default Notes folder and tells the caller what happened.

---

## Why This Exists

The app's pipeline will classify voice memo transcripts and route some of them to Apple Notes, but the pipeline currently has no way to discover the user's folder structure or create notes in specific locations. Without this capability, all routed notes would land in the same place regardless of how the user organizes their Notes library, making folder-targeted routing impossible.

---

## Scope

### In
- A protocol defining Notes service capabilities (list folders, resolve hierarchy, create note)
- Folder discovery: list top-level folders and subfolders within a given folder
- Folder hierarchy resolution: return the path from root to a given folder (e.g., "Finance → Taxes")
- Note creation in a specified folder, with fallback to the default Notes folder
- A concrete implementation backed by AppleScript
- A minimal verification capability for integration tests (confirm a note exists in a folder)
- Unit tests for the protocol contract using a mock implementation
- Integration-style tests for the concrete implementation

### Out (explicitly)
- Full note reading (content retrieval) — only minimal existence verification for tests
- Creating or renaming folders — the service reads existing folder structure only
- Rich text or HTML note formatting — notes receive plain text content
- Calendar or Reminders integration — separate services, separate plans
- UI for folder selection or mapping — no UI work in this plan
- Pipeline integration (wiring the Notes service into the classification/routing stage)

---

## Technical Context

- **Platform**: macOS 15+ (Sequoia), Swift 6.2 with strict concurrency (`complete`)
- **Project structure**: Protocols live in `Libraries/Sources/Core/`; concrete macOS-specific implementations live in `Utterd/Core/` (established pattern: `TranscriptionService` protocol → `SpeechAnalyzerTranscriptionService` concrete)
- **Apple Notes access**: No direct Swift API exists. AppleScript via `NSAppleScript` or `Process` running `osascript` is the chosen mechanism. The spec originally recorded "Scripting Bridge" but AppleScript was chosen for its simpler integration model (spec updated to reflect this)
- **Concurrency requirements**: Protocols must be `Sendable`. AppleScript execution is synchronous and should not block the main actor
- **Testing**: Swift Testing (`@Test`, `#expect`). Mocks live in `Libraries/Tests/CoreTests/Mocks/`

---

## User Stories

### US-01 — Discover Notes folders
As a classification pipeline,
I want to retrieve the user's Notes folder structure,
So that I can resolve which folder a transcript should be routed to.

**Acceptance Criteria**
- [ ] AC-01.1: GIVEN the user has top-level folders named "Finance" and "Personal" in Apple Notes, WHEN the service lists top-level folders, THEN it returns exactly two folder entries whose names are "Finance" and "Personal", in any order
- [ ] AC-01.2: GIVEN a folder contains subfolders, WHEN the service lists subfolders for that folder, THEN all immediate child folders are returned with their names
- [ ] AC-01.3: GIVEN a folder object representing "Taxes" inside "Finance" was returned by a previous folder listing, WHEN the service resolves the hierarchy for that folder, THEN it returns the path ["Finance", "Taxes"] in root-to-leaf order
- [ ] AC-01.4: GIVEN the user has no custom folders in Apple Notes, WHEN the service lists top-level folders, THEN an empty list is returned (the default Notes folder is not included in folder listings)
- [ ] AC-01.7: GIVEN two folders with the same name exist at different levels (e.g., "Taxes" under "Finance" and "Taxes" under "Personal"), WHEN both are returned by folder listings, THEN the two folder references are not equal, and each carries at minimum a display name and a stable identity that distinguishes it from the other
- [ ] AC-01.5: GIVEN Apple Notes is not accessible (not running, permission denied, or unavailable), WHEN the service attempts to list folders, THEN a descriptive error is thrown specifying the failure reason
- [ ] AC-01.6: GIVEN the Automation permission has not been granted, WHEN the service attempts to list folders, THEN a permission-specific error is thrown that the caller can distinguish from other failures

### US-02 — Create a note in a folder
As a classification pipeline,
I want to create a note in a specific Notes folder,
So that the transcript is stored where the user expects to find it.

**Acceptance Criteria**
- [ ] AC-02.1: GIVEN a valid folder reference and text content, WHEN the service creates a note, THEN a new note appears in that folder with the provided content
- [ ] AC-02.2: GIVEN no folder is specified, WHEN the service creates a note, THEN the note is created in the user's default Notes folder
- [ ] AC-02.3: GIVEN a folder reference that no longer exists, WHEN the service creates a note, THEN the note is created in the default Notes folder and the result indicates that fallback occurred
- [ ] AC-02.4: GIVEN Apple Notes is not running, WHEN the service creates a note, THEN the note is still created successfully (the underlying mechanism launches Notes if needed)
- [ ] AC-02.5: GIVEN the underlying Notes access fails (e.g., permission denied), WHEN the service attempts to create a note, THEN a descriptive error is thrown to the caller
- [ ] AC-02.6: GIVEN two folders with the same name exist at the same level, WHEN the service creates a note using one of those folder references, THEN the note is created in the specific folder identified by the reference, not an arbitrary match

### US-03 — Verify note existence (test support)
As an integration test,
I want to verify that a note was created in a specific folder,
So that I can confirm the service works end-to-end.

**Acceptance Criteria**
- [ ] AC-03.1: GIVEN a note was just created in a folder, WHEN the service checks for recent notes in that folder, THEN it confirms the note exists
- [ ] AC-03.2: GIVEN no note was created in a folder, WHEN the service checks for recent notes in that folder matching a specific title, THEN it reports the note was not found

---

## Edge Cases

- **Apple Notes not installed or disabled**: The service throws a clear error rather than silently failing or hanging
- **Automation permission not granted**: macOS requires the user to grant Automation permission for the app to control Notes. If denied, the service throws a distinguishable permission error
- **Folder names with special characters**: Folder names containing quotes, backslashes, or unicode characters must be safely escaped to prevent injection or corruption in the underlying script execution
- **Duplicate folder names at the same level**: Apple Notes allows this. The service returns all folders as distinct references; the caller uses the reference (not just the name string) to target a specific folder
- **Duplicate folder names at different nesting levels**: Hierarchy resolution uses a folder reference from a prior listing, not a bare name string, so "Taxes" under "Finance" and "Taxes" under "Personal" are unambiguous
- **Very large folder hierarchies**: The service does not assume a shallow tree — users may have deeply nested structures. No arbitrary depth limits
- **Concurrent calls**: Multiple pipeline invocations may call the service simultaneously. Concurrent calls must produce the same results as sequential calls — no lost notes, no crossed folder references, no partial failures
- **Empty note content**: If the caller passes an empty string, the service still creates the note (empty notes are valid in Apple Notes)
- **Notes app state during folder enumeration**: Apple Notes may be open, closed, or in a background state. The service behaves consistently regardless

---

## Success Criteria

1. Zero acceptance criteria in US-01 through US-03 lack a corresponding automated test — confirmed by test-plan traceability at PR merge
2. The concrete implementation can list folders and create a note in a targeted folder on a machine with Apple Notes present
3. Zero script injection vulnerabilities — all user-supplied strings are escaped before interpolation into scripts
4. The protocol is the sole interface between the service and its callers — no caller imports the concrete implementation type. Unit tests run against a mock; integration tests run against the real implementation. Both verify the same behavioral contract (same ACs), demonstrating substitutability

---

## Dependencies & Assumptions

**Dependencies**
- Apple Notes app installed on the user's machine (ships with macOS)
- macOS Automation permission granted by the user for Utterd to control Notes
- Project spec: `spec.md` (updated to reflect AppleScript choice)

**Assumptions**
- AppleScript can enumerate Notes folders and their hierarchy (the Notes AppleScript dictionary supports `folder` objects with `name` and `container` properties)
- AppleScript can create a note in a specific folder with plain text body
- The default Notes folder is accessible without knowing its explicit name (AppleScript's `default account` or similar mechanism)
- Automation permission prompts are handled by macOS automatically on first use; the service does not need to trigger or manage permission dialogs
- AppleScript's `tell application` mechanism launches Notes automatically if it is not running (AC-02.4 depends on this)
- Folder references returned by listing operations remain valid for at least the duration of a single pipeline run (folders are not renamed/deleted mid-operation)

---

## Open Questions

- [x] Should the first concrete implementation use AppleScript or Scripting Bridge?
  - Context: The spec records "Scripting Bridge" as the chosen mechanism, but AppleScript is simpler to integrate and more commonly used for Notes automation. The choice affects type safety, injection risk, and implementation complexity
  - Options considered: AppleScript (`NSAppleScript`/`osascript`) — simpler, well-documented, string-based; Scripting Bridge (`ScriptingBridge.framework`) — type-safe generated interfaces, less documented for Notes
  - Decision needed by: Before implementation planning
  - Decision: AppleScript
  - Reasoning: Simpler integration model for the first implementation. The protocol abstraction means we can swap to Scripting Bridge or a future Apple API later without changing callers. The spec should be updated to reflect this decision

- [x] How should integration tests verify that a note was created in the correct folder?
  - Context: "Reading notes" was initially out of scope, but integration tests need some way to confirm note creation actually worked
  - Options considered: (a) Add minimal verification-only read capability, (b) defer integration verification entirely, (c) count notes before/after as a crude check
  - Decision needed by: Before implementation planning
  - Decision: Option (a) — add a minimal verification capability scoped to test support
  - Reasoning: Without verification, integration tests can only confirm the service didn't throw an error, not that it actually created the note. A minimal check (note exists in folder) is sufficient without building full read-note-content functionality

- [x] Should the default Notes folder appear in folder listings?
  - Context: If excluded, the pipeline cannot discover it programmatically. If included, it needs to be distinguishable from user-created folders
  - Options considered: Include with a flag, exclude entirely, include as a regular entry
  - Decision needed by: Before implementation planning
  - Decision: Exclude — the default folder does not appear in listings
  - Reasoning: The default folder is the implicit fallback target. The pipeline doesn't need to "discover" it — it's where notes go when no specific folder is requested. Including it would add complexity to distinguish it from user folders

---

## Out of Scope (Clarification)

- **Full note reading** — discussed as a potential confirmation mechanism and for future features. Only minimal existence verification (for integration tests) is in scope. Full content retrieval can be added to the protocol later without breaking existing implementations
- **Shared DestinationService protocol across Notes/Calendar/Reminders** — discussed whether all three destinations should share a common interface. Deferred because the three services have fundamentally different capabilities (folders vs. calendars vs. lists) and a forced common abstraction would be leaky. Each gets its own protocol
- **Folder creation** — discussed whether to auto-create missing folders. Decided to fall back to the default folder instead, keeping the service read-only for folder structure
- **UI for folder mapping** — mentioned as a potential future feature for letting users map categories to folders. No UI work in this plan
- **Spec update for Scripting Bridge → AppleScript** — completed; spec.md updated in this branch
