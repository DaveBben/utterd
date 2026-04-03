# Descope LLM Routing — Task Breakdown

**Plan**: docs/plans/descope-llm-routing/plan.md
**Date**: 2026-04-02
**Status**: Approved

---

## Key Decisions

- **Pipeline init signature unchanged**: `NoteRoutingPipelineStage` keeps the same
  8-parameter initializer (`notesService`, `llmService`, `summarizer`, `store`, `logger`,
  `configProvider`, `contextBudget`, `onComplete`). `llmService` shifts from powering
  classification to powering title generation; `summarizer` continues to handle
  summarization. AppDelegate requires no changes — it already creates and injects the right
  services.

- **Default folder resolution is lazy**: `resolveDefaultFolder` only calls
  `notesService.listFolders(in: nil)` when `config.defaultFolderName` is non-nil. When nil,
  it returns nil immediately (system default). This avoids unnecessary AppleScript calls.
  The `FolderHierarchyCache` actor is removed entirely.

- **Title generation uses word splitting, not linguistic analysis**: The first 2,000 words
  are extracted via `transcript.split(separator: " ").prefix(2000).joined(separator: " ")`,
  consistent with how the existing code counts words for the context budget check. No need
  for `NLTokenizer`.

- **Stale UserDefaults keys removed in init**: `UserSettings.init` proactively removes
  `useCustomPrompt`, `customPrompt`, and `llmEnabled` keys from `UserDefaults` to prevent
  stale data persisting from the old routing system (EC-06).

- **PipelineControllerTests updated in Task 1**: These tests create `RoutingConfiguration`
  instances with the old `llmApproach` enum. Updating them alongside the pipeline rewrite
  keeps `swift test` passing at the first opportunity. The changes are mechanical — replacing
  enum-based constructors with boolean-based ones.

- **Title sanitization follows existing pattern**: The sanitization logic (strip
  newlines/null/tab, truncate to 100 chars, date fallback on empty) is preserved from the
  current `sanitizedTitle` closure in `routeCore()`. Only the source changes — from
  classifier result to LLM title generation response.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|---|---|
| AC-01.1 (no LLM calls when both off) | Task 1 |
| AC-02.1 (short transcript summarized) | Task 2 |
| AC-02.2 (long transcript summarized) | Task 2 |
| AC-02.3 (empty transcript no summarize) | Task 2 |
| AC-02.4 (empty summary → full transcript) | Task 2 |
| AC-03.1 (title: 2K word truncation) | Task 3 |
| AC-03.2 (LLM title used) | Task 3 |
| AC-03.3 (empty transcript → date title) | Task 3 |
| AC-03.4 (title >100 chars → truncated) | Task 3 |
| AC-03.5 (empty LLM title → date fallback) | Task 3 |
| AC-03.6 (multi-line → first line) | Task 3 |
| AC-04.1 (both features independent) | Task 3 |
| AC-04.2 (summarize ok + title fails) | Task 3 |
| AC-04.3 (title ok + summarize fails) | Task 3 |
| AC-05.1 (summarize fails → full transcript) | Task 2 |
| AC-05.2 (title fails → date title) | Task 3 |
| AC-06.1 (fresh install defaults) | Task 4 |
| AC-06.2 (macOS <26 toggles disabled) | Task 4 (visual verification) |
| AC-07.1 (no routing code remnants) | Task 0, Task 5 |
| EC-01 (empty transcript) | Task 1, Task 2, Task 3 |
| EC-02 (word count = budget exactly) | Task 2 |
| EC-03 (empty LLM title) | Task 3 |
| EC-04 (long title >100 chars) | Task 3 |
| EC-05 (default folder missing) | Task 1 |
| EC-06 (stale UserDefaults keys) | Task 4 |
| EC-07 (both on + LLM unavailable) | Task 3 |
| EC-08 (title <2K words → full transcript) | Task 3 |
| EC-09 (config snapshot) | Existing behavior, no task |
| EC-10 (empty summary → full transcript) | Task 2 |
| SC-1 (xcodebuild passes) | Task 5 |
| SC-2 (swift test passes) | Task 1+ |
| SC-3 (no routing code remnants) | Task 0, Task 5 |
| Integration: title generation | Task 5 |
| Integration: summarization quality | Task 5 |
| spec.md update | Task 5 |
| CLAUDE.md update | Task 5 |

---

## Tasks

### Task 0: Rewrite RoutingConfiguration + Delete Routing Code

**Relevant Files:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` ← rewrite
- `Libraries/Sources/Core/NotesService.swift` ← remove `resolveHierarchy(for:)` method
- `Libraries/Sources/Core/TranscriptClassifier.swift` ← delete
- `Libraries/Sources/Core/NoteClassificationResult.swift` ← delete
- `Libraries/Sources/Core/RoutingMode.swift` ← delete
- `Libraries/Sources/Core/FolderHierarchyBuilder.swift` ← delete
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` ← remove `resolveHierarchy` method
- `Libraries/Tests/CoreTests/TranscriptClassifierTests.swift` ← delete
- `Libraries/Tests/CoreTests/FolderHierarchyBuilderTests.swift` ← delete
- `UtterdTests/TranscriptClassifierIntegrationTests.swift` ← delete

**Context to Read First:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` — read current struct to understand
  all three existing properties and their defaults before rewriting, so nothing is
  accidentally dropped
- `Libraries/Sources/Core/NotesService.swift` — protocol that defines
  `resolveHierarchy(for:)` which must be removed (only consumer is the deleted
  `buildFolderHierarchy`)
- `docs/plans/descope-llm-routing/plan.md` (lines 145–153) — new config properties

**Steps:**

1. [ ] Rewrite `RoutingConfiguration.swift`: remove the `LLMApproach` enum entirely.
   The struct becomes three public stored properties: `summarizationEnabled: Bool`
   (default `false`), `titleGenerationEnabled: Bool` (default `false`),
   `defaultFolderName: String?` (default `nil`). Keep `Sendable, Equatable` conformance
   and the public memberwise initializer with defaults.
2. [ ] Remove `resolveHierarchy(for:)` from `NotesService.swift` protocol (its only
   consumer, `buildFolderHierarchy`, is being deleted). Remove the corresponding method
   and stored properties from `MockNotesService.swift` (`resolveHierarchyResult`,
   `resolveHierarchyError`, `resolveHierarchyCalls`, and the `resolveHierarchy` function)
3. [ ] Delete the four source files: `TranscriptClassifier.swift`,
   `NoteClassificationResult.swift`, `RoutingMode.swift`, `FolderHierarchyBuilder.swift`
4. [ ] Delete the three test files: `TranscriptClassifierTests.swift`,
   `FolderHierarchyBuilderTests.swift`, `TranscriptClassifierIntegrationTests.swift`
5. [ ] Verify `RoutingConfiguration.swift` compiles standalone (the Libraries package and
   app target will not compile until Task 1 rewrites `NoteRoutingPipelineStage` and Task 4
   rewrites `UserSettings`/`SettingsView` — that is expected)

**Acceptance Criteria:**

- GIVEN the rewritten `RoutingConfiguration.swift`, WHEN compiled, THEN it defines a
  `Sendable, Equatable` struct with three public properties:
  `summarizationEnabled: Bool`, `titleGenerationEnabled: Bool`,
  `defaultFolderName: String?`, all with default values `false`, `false`, `nil`
- GIVEN the updated `NotesService.swift`, WHEN searching for `resolveHierarchy`, THEN
  zero matches in `NotesService.swift` and `MockNotesService.swift`
- GIVEN the repository after deletions, WHEN searching Swift source files for
  `TranscriptClassifier`, `NoteClassificationResult`, `RoutingMode`,
  `FolderHierarchyEntry`, `buildFolderHierarchy`, THEN zero matches are found
  (excluding plan/doc files)

**Do NOT:**
- Modify `NoteRoutingPipelineStage.swift` — that is Task 1
- Modify `UserSettings.swift` or `SettingsView.swift` — that is Task 4
- Modify `AppleScriptNotesService.swift` — it still conforms to `NotesService` even
  without `resolveHierarchy` (extra methods on a conformer are harmless); cleanup is in
  Task 4
- Modify any test files other than the three being deleted and `MockNotesService.swift`
- Add migration logic or compatibility shims for the old `LLMApproach` enum

---

### Task 1: Rewrite NoteRoutingPipelineStage — No-LLM Path + Default Folder Resolution

**Blocked By:** Task 0

**Relevant Files:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` ← rewrite
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` ← rewrite
- `Libraries/Tests/CoreTests/PipelineControllerTests.swift` ← update config constructors

**Context to Read First:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` — new config shape from Task 0
  (three booleans, no enum)
- `Libraries/Sources/Core/NotesService.swift` — `listFolders(in:)` method used for flat
  folder lookup in the rewritten `resolveDefaultFolder`
- `Libraries/Sources/Core/DateFallbackTitle.swift` — `dateFallbackTitle(for:)` free
  function generates "Voice Memo YYYY-MM-DD HH:mm" titles
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` — mock with
  `listFoldersByParent` dictionary (key `nil` returns root-level folders) and
  `createNoteCalls` capture array
- `Libraries/Tests/CoreTests/Mocks/MockLLMService.swift` — mock with `result`, `error`,
  and `calls` array; single `result` property (one return value per test)
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptSummarizer.swift` — mock with `result`,
  `error`, and `calls` array
- `Libraries/Sources/Core/LLMContextBudget.swift` — `availableForContent` property
  (still used by summarizer in Task 2)

**Steps:**

1. [ ] Delete all existing content from `NoteRoutingPipelineStageTests.swift` — the old
   tests reference deleted types (`LLMApproach`, `RoutingMode`, `FolderHierarchyEntry`)
   and will not compile. Write a new `NoteRoutingPipelineStageTests` struct with a
   `makeStage` helper that constructs the stage with default config
   `RoutingConfiguration()` (both toggles off). Include helpers
   `makeURL()`, `makePersonalFolder()`, `smallBudget()`, `tinyBudget()` matching the
   existing pattern. Write 7 tests:
   - Both toggles off + normal transcript → `MockLLMService.calls` empty,
     `MockTranscriptSummarizer.calls` empty, note body is full transcript, title is
     date-based (plan scenario 1)
   - Both toggles off + empty transcript → no LLM/summarizer calls, empty body,
     date title (plan scenario 7)
   - `defaultFolderName` is "personal" + `listFolders(in: nil)` returns matching folder →
     note created in that folder (plan scenario 18)
   - `defaultFolderName` is "Gone" + no folder matches → note created with
     `folder: nil` (plan scenario 19)
   - `defaultFolderName` is set + `listFolders(in: nil)` throws → note created with
     `folder: nil`, warning logged (plan scenario 20)
   - `markProcessed` + `onComplete` run exactly once on success path
     (plan scenario 21)
   - `markProcessed` + `onComplete` run exactly once on error path
     (plan scenario 22)
2. [ ] Run `cd Libraries && timeout 120 swift test </dev/null 2>&1` to verify tests fail
   (compilation errors expected — `NoteRoutingPipelineStage` still references deleted types)
3. [ ] Rewrite `NoteRoutingPipelineStage.swift`:
   - Remove the `FolderHierarchyCache` private actor entirely
   - Remove the `folderCache` stored property
   - Keep the same public init signature (8 parameters unchanged)
   - Rewrite `routeCore(transcript:now:)`: read config via `configProvider()`, call
     `resolveDefaultFolder(config.defaultFolderName)` to get the target folder, create
     the note with `dateFallbackTitle(for: now)` as title and `transcript` as body.
     **Leave placeholder comments** for summarization (Task 2) and title generation
     (Task 3) — do not implement those paths yet
   - Rewrite `resolveDefaultFolder(_ name: String?) async -> NotesFolder?`: if name is
     nil return nil; otherwise call `notesService.listFolders(in: nil)`, find first
     folder where `folder.name == name`, return it. On no match return nil. On error
     log a warning via `logger.warning(...)` and return nil
   - Keep `route()` outer method unchanged — same do/catch wrapping `routeCore`,
     same `markProcessed`, same `onComplete` call
4. [ ] Update `PipelineControllerTests.swift`: replace all
   `RoutingConfiguration(llmApproach: .autoRoute)` with `RoutingConfiguration()`.
   The `llmService.result` assignments are harmless (LLM never called with both toggles
   off) and can stay. No behavioral test changes needed — with both toggles off the
   pipeline still creates a note with the transcript body, which is what these tests
   verify
5. [ ] Run `cd Libraries && timeout 120 swift test </dev/null 2>&1` to verify all tests
   pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN both `summarizationEnabled` and `titleGenerationEnabled` are false, WHEN
  `route()` is called with transcript "Buy groceries", THEN
  `MockLLMService.calls` is empty, `MockTranscriptSummarizer.calls` is empty,
  `notesService.createNote` is called once with body "Buy groceries" and title equal to
  `dateFallbackTitle(for: now)` (the exact output of the free function in
  `DateFallbackTitle.swift`, format: `"Voice Memo YYYY-MM-DD HH:mm"` in GMT)
- GIVEN both toggles off and empty transcript, WHEN `route()` is called, THEN note is
  created with empty body and title equal to `dateFallbackTitle(for: now)`, no LLM or
  summarizer calls
- GIVEN `defaultFolderName` "personal" and
  `notesService.listFolders(in: nil)` returns
  `[NotesFolder(id: "personal", name: "personal")]`, WHEN `route()` is called, THEN
  `notesService.listFoldersCalls` contains exactly one entry (`nil` — flat call, no
  recursion) AND note is created with `folder == personal`
- GIVEN `defaultFolderName` "Gone" and no matching folder, WHEN `route()` is called,
  THEN note is created with `folder: nil` (system default)
- GIVEN `defaultFolderName` set and `listFolders(in: nil)` throws, WHEN `route()` is
  called, THEN note is created with `folder: nil` and `logger.warnings.count >= 1`
- GIVEN any outcome (success or error), WHEN `route()` completes, THEN
  `store.markProcessed` and `onComplete` are each called exactly once
- GIVEN `PipelineControllerTests` with updated config constructors, WHEN
  `swift test` runs, THEN all controller tests pass

**Do NOT:**
- Implement summarization conditional logic — leave a placeholder comment; Task 2 adds it
- Implement title generation logic — leave a placeholder comment; Task 3 adds it
- Modify `AppDelegate.swift` — it works without changes (same init signature)
- Modify `UserSettings.swift` or `SettingsView.swift` — those are Task 4
- Add the LLM system prompt for title generation — Task 3 handles that
- Change the init signature or add/remove parameters

---

### Task 2: Pipeline — Summarization Path

**Blocked By:** Task 1

**Relevant Files:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` ← update `routeCore()`
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` ← add tests

**Context to Read First:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` — current `routeCore()`
  from Task 1 (with summarization placeholder comment)
- `Libraries/Sources/Core/TranscriptSummarizer.swift` —
  `summarize(transcript:contextBudget:)` protocol; the pipeline calls this directly
- `Libraries/Sources/Core/LLMContextBudget.swift` — `availableForContent` property;
  previously used to decide if summarization was needed, now irrelevant for the gate
  (all transcripts are summarized when toggle is on) but still passed to the summarizer
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptSummarizer.swift` — mock captures
  `calls` array and returns configurable `result` or throws `error`
- `docs/plans/descope-llm-routing/plan.md` (lines 279–285) — behavior change: ALL
  transcripts are now summarized when the toggle is on, regardless of length

**Steps:**

1. [ ] Write 5 failing tests in `NoteRoutingPipelineStageTests`:
   - Summarization on + short transcript ("Buy groceries") → summarizer called once
     with full transcript, note body is summarizer's return value, title is date-based
     (plan scenario 2)
   - Summarization on + long transcript (word count exceeds
     `contextBudget.availableForContent`) → summarizer called, note body is summarizer's
     return value (plan scenario 3)
   - Summarization on + empty transcript → summarizer NOT called, empty body, date title
     (plan scenario 8)
   - Summarization on + summarizer throws → note body is the full transcript, error
     logged (plan scenario 10)
   - Summarization on + summarizer returns empty string → note body is the full
     transcript (plan scenario 17)
2. [ ] Run `cd Libraries && timeout 120 swift test </dev/null 2>&1` to verify the 5 new
   tests fail
3. [ ] Add summarization conditional to `routeCore()` (replace the placeholder comment):
   after resolving the default folder and before creating the note, check
   `config.summarizationEnabled && !transcript.isEmpty`. If true, call
   `summarizer.summarize(transcript:contextBudget:)` inside a do/catch. On success,
   use the summary as the note body — unless the summary is empty, in which case fall
   back to the full transcript. On error, log via `logger.error(...)` and keep the full
   transcript as body
4. [ ] Run `cd Libraries && timeout 120 swift test </dev/null 2>&1` to verify all tests
   pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN summarization on and transcript "Buy groceries" (2 words, under budget), WHEN
  `route()` is called, THEN `MockTranscriptSummarizer.calls.count == 1` and
  `calls[0].transcript == "Buy groceries"` and note body is the summarizer's return value
- GIVEN summarization on and transcript exceeding `contextBudget.availableForContent`
  words, WHEN `route()` is called, THEN `MockTranscriptSummarizer.calls.count == 1` and
  `calls[0].transcript` equals the full unmodified transcript and note body is the
  summarizer's return value
- GIVEN summarization on and empty transcript, WHEN `route()` is called, THEN
  `MockTranscriptSummarizer.calls` is empty and note body is empty
- GIVEN summarization on and summarizer throws, WHEN `route()` is called, THEN note body
  is the full transcript and `logger.errors.count == 1`
- GIVEN summarization on and summarizer returns `""`, WHEN `route()` is called, THEN note
  body is the full transcript (fallback)

**Do NOT:**
- Implement title generation logic — Task 3 handles that
- Modify the `route()` outer method — only modify `routeCore()`
- Change the init signature or add new parameters
- Add tests for title generation or combined behavior — Task 3 covers those
- Gate summarization on word count — in the new design, ALL non-empty transcripts are
  summarized when the toggle is on (the summarizer handles chunking internally)

---

### Task 3: Pipeline — Title Generation + Combined Behavior

**Blocked By:** Task 2

**Relevant Files:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` ← update `routeCore()`
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` ← add tests

**Context to Read First:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` — current `routeCore()` from
  Task 2 (summarization is now implemented, title generation placeholder remains)
- `Libraries/Sources/Core/LLMService.swift` —
  `generate(systemPrompt:userPrompt:) async throws -> String` protocol used for title
  generation
- `Libraries/Tests/CoreTests/Mocks/MockLLMService.swift` — mock with single `result`
  property and `calls` array. **Important**: title generation calls
  `llmService.generate()` exactly once per `route()` invocation. Summarization uses
  `MockTranscriptSummarizer` (separately mockable), NOT `MockLLMService`. This is why
  the single `result` property is sufficient — `MockLLMService` is only called once per
  test for title generation
- `docs/plans/descope-llm-routing/plan.md` (lines 256–266) — title generation call
  design: system prompt, input truncation, response parsing

**Steps:**

1. [ ] Write 11 failing tests in `NoteRoutingPipelineStageTests`:
   - Title gen on + normal transcript → `MockLLMService.calls.count == 1`, system prompt
     contains "title", user prompt is the transcript, note title is the LLM response
     after sanitization (plan scenario 4)
   - Title gen on + transcript >2K words → `MockLLMService.calls[0].userPrompt` contains
     exactly 2,000 words (plan scenario 5). Build the transcript as
     `(1...3000).map { "word\($0)" }.joined(separator: " ")`
   - Both on + normal transcript → `MockTranscriptSummarizer.calls.count == 1` AND
     `MockLLMService.calls.count == 1`, note body is summary, note title is LLM response
     (plan scenario 6)
   - Title gen on + empty transcript → `MockLLMService.calls` is empty, title is
     date-based (plan scenario 9)
   - Title gen on + LLM throws → title is date-based, `logger.errors` contains a title
     generation failure message (plan scenario 11)
   - Both on + summarize succeeds + title gen throws → body is summary, title is
     date-based, error logged (plan scenario 12)
   - Both on + summarize throws + title gen succeeds → body is full transcript, title is
     LLM-generated, error logged (plan scenario 13)
   - Title gen on + LLM returns `""` → title is date-based (plan scenario 14)
   - Title gen on + LLM returns 150-char string → title is truncated to 100 chars
     (plan scenario 15)
   - Title gen on + LLM returns `"Line1\n\nLine3"` → title is `"Line1"`
     (plan scenario 16)
   - Both on + both summarizer and LLM throw → body is full transcript, title is
     date-based, both errors logged independently (EC-07)
2. [ ] Run `cd Libraries && timeout 120 swift test </dev/null 2>&1` to verify the 11 new
   tests fail
3. [ ] Add title generation to `routeCore()` (replace the placeholder comment). After the
   summarization block (which runs independently), if
   `config.titleGenerationEnabled && !transcript.isEmpty`:
   - Extract first 2,000 words:
     `transcript.split(separator: " ").prefix(2000).joined(separator: " ")`
   - Define the system prompt: a string instructing the model to generate a short
     descriptive title for the voice memo transcript and return only the title, nothing
     else (e.g., `"Generate a short descriptive title for this voice memo transcript.
     Return only the title, nothing else."`)
   - Call `llmService.generate(systemPrompt:userPrompt:)` with the system prompt and
     the truncated transcript as user prompt
   - Parse response: split by `"\n"` omitting empty subsequences, take the first
     element, convert to `String`
   - Sanitize: filter out characters matching `$0.isNewline || $0 == "\0" || $0 == "\t"`,
     then truncate to 100 characters via `.prefix(100)`
   - If the sanitized result is non-empty, use it as the title (replacing the date-based
     default)
   - Wrap the entire title generation block in a do/catch. On error, log via
     `logger.error(...)` and keep the date-based title
4. [ ] Verify that summarization and title generation are fully independent: each has its
   own do/catch, each can succeed or fail without affecting the other. The note is always
   created — failures only affect which body or title is used
5. [ ] Run `cd Libraries && timeout 120 swift test </dev/null 2>&1` to verify all tests
   pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN title gen on and transcript "Buy groceries", WHEN `route()` is called, THEN
  `MockLLMService.calls.count == 1` and system prompt contains "title" and user prompt
  is "Buy groceries" and note title is the mock's `result` (after sanitization)
- GIVEN title gen on and transcript with 3,000 words, WHEN `route()` is called, THEN
  `MockLLMService.calls[0].userPrompt.split(separator: " ").count == 2000`
- GIVEN both toggles on, WHEN `route()` is called, THEN
  `MockTranscriptSummarizer.calls.count == 1` AND `MockLLMService.calls.count == 1` —
  separate, independent calls
- GIVEN title gen on and empty transcript, WHEN `route()` is called, THEN
  `MockLLMService.calls` is empty and title equals `dateFallbackTitle(for: now)`
- GIVEN title gen on and LLM throws, WHEN `route()` is called, THEN title is date-based
  and `logger.errors.count == 1`
- GIVEN both on + summarize succeeds + title gen throws, WHEN `route()` is called, THEN
  body is the summary, title is date-based, and `logger.errors.count == 1`
- GIVEN both on + summarize throws + title gen succeeds, WHEN `route()` is called, THEN
  body is full transcript, title is the LLM response, and `logger.errors.count == 1`
- GIVEN both on + both throw, WHEN `route()` is called, THEN body is full transcript,
  title is date-based, and `logger.errors.count >= 2` (one per independent failure)
- GIVEN title gen on and LLM returns `""`, WHEN `route()` is called, THEN title is
  date-based
- GIVEN title gen on and LLM returns a 150-character string, WHEN `route()` is called,
  THEN note title is exactly 100 characters
- GIVEN title gen on and LLM returns `"Line1\n\nLine3"`, WHEN `route()` is called, THEN
  title is `"Line1"`

**Do NOT:**
- Modify the `route()` outer method — only modify `routeCore()`
- Change the init signature or add new parameters
- Modify `UserSettings.swift`, `SettingsView.swift`, or `AppDelegate.swift`
- Create a new `TitleGenerator` protocol — call `llmService.generate()` directly per the
  plan's design decision
- Modify existing summarization logic from Task 2 — title generation is additive

---

### Task 4: Rewrite UserSettings + SettingsView

**Blocked By:** Task 1 (Libraries must compile for `xcodebuild` to build the app target)

**Relevant Files:**
- `Utterd/Core/UserSettings.swift` ← rewrite
- `Utterd/Features/Settings/SettingsView.swift` ← rewrite
- `Utterd/Core/AppleScriptNotesService.swift` ← remove dead `resolveHierarchy` method
- `UtterdTests/NotesServiceListingTests.swift` ← remove `resolveHierarchy` tests + update suite name
- `UtterdTests/AppleScriptNotesServiceIntegrationTests.swift` ← remove `resolveHierarchyContainsFolderItself` test
- `UtterdTests/SettingsRoutingModelTests.swift` ← remove dead `resolveHierarchy` stub from `MockNotesServiceForSettings`
- `UtterdTests/UserSettingsTests.swift` ← rewrite
- `UtterdTests/SettingsLLMSectionTests.swift` ← rewrite

**Context to Read First:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` — new config shape from Task 0
  (three properties, no enum)
- `Utterd/Core/UserSettings.swift` — current properties, `Keys` enum, and
  `toRoutingConfiguration()` mapping that references `RoutingConfiguration.LLMApproach`
  and `TranscriptClassifier.defaultCustomPrompt`
- `Utterd/Features/Settings/SettingsView.swift` — current UI with routing mode picker,
  custom prompt TextEditor, and "Reset to Default" button that must all be removed
- `Utterd/Features/Settings/SettingsRoutingModel.swift` — folder picker model (survives
  unchanged — still loads top-level folders for the folder picker)
- `UtterdTests/UserSettingsTests.swift` — existing test patterns: isolated
  `UserDefaults(suiteName:)` per test with `removePersistentDomain` in defer
- `Utterd/Core/AppleScriptNotesService.swift` — has `resolveHierarchy(for:)` method that
  is now dead code after Task 0 removed it from the protocol

**Steps:**

1. [ ] Delete all existing content from `UserSettingsTests.swift` and
   `SettingsLLMSectionTests.swift` — the old tests reference deleted types
   (`TranscriptClassifier.defaultCustomPrompt`, `LLMApproach`, `llmEnabled`,
   `useCustomPrompt`) and will not compile. Write a new `UserSettingsTests` struct:
   - Fresh defaults: `summarizationEnabled == false`, `titleGenerationEnabled == false`,
     `defaultFolderName == nil` — no references to `llmEnabled`, `useCustomPrompt`, or
     `customPrompt`
   - `titleGenerationEnabled` persists across re-init
   - `summarizationEnabled` persists across re-init
   - `defaultFolderName` persists across re-init
   - `toRoutingConfiguration()` with both false →
     `RoutingConfiguration(summarizationEnabled: false, titleGenerationEnabled: false)`
   - `toRoutingConfiguration()` with both true →
     `RoutingConfiguration(summarizationEnabled: true, titleGenerationEnabled: true)`
   - `toRoutingConfiguration()` maps `defaultFolderName` correctly
   - Stale key cleanup: given defaults with `useCustomPrompt`, `customPrompt`, and
     `llmEnabled` keys set, after `UserSettings` init, those keys are nil in defaults
2. [ ] Write failing tests in `SettingsLLMSectionTests.swift`. Replace the existing test
   struct:
   - Fresh defaults → both toggles off in config
   - Only `summarizationEnabled` on → config has only `summarizationEnabled: true`
   - Only `titleGenerationEnabled` on → config has only `titleGenerationEnabled: true`
3. [ ] Run `xcodebuild -scheme Utterd -destination 'platform=macOS' test` to verify tests
   fail (compilation errors expected — `UserSettings` still references deleted types)
4. [ ] Rewrite `UserSettings.swift`:
   - Remove Keys: `llmEnabled`, `useCustomPrompt`, `customPrompt`
   - Add Key: `titleGenerationEnabled`
   - Remove properties: `llmEnabled`, `useCustomPrompt`, `customPrompt`
   - Add property: `titleGenerationEnabled` (Bool, backed by UserDefaults key
     `"titleGenerationEnabled"`, same access/mutation pattern as existing properties)
   - Keep properties: `defaultFolderName`, `summarizationEnabled`
   - In `init(defaults:)`: add stale key cleanup — call
     `defaults.removeObject(forKey:)` for `"useCustomPrompt"`, `"customPrompt"`, and
     `"llmEnabled"`
   - Rewrite `toRoutingConfiguration()`: return
     `RoutingConfiguration(summarizationEnabled: summarizationEnabled,
     titleGenerationEnabled: titleGenerationEnabled,
     defaultFolderName: defaultFolderName)`
   - Rewrite `readRoutingConfiguration(from:)`: read the three keys from defaults and
     return the new `RoutingConfiguration`
5. [ ] Rewrite `SettingsView.swift`:
   - Remove the routing mode picker (`Picker("Routing Mode", ...)`)
   - Remove the custom prompt TextEditor and "Reset to Default" button
   - Remove the `if settings.llmEnabled { ... }` conditional wrapper — both toggles are
     always visible
   - Change the LLM section to contain two toggles:
     `Toggle("Enable Summarization", isOn: $settings.summarizationEnabled)` and
     `Toggle("Enable Title Generation", isOn: $settings.titleGenerationEnabled)`, both
     with `.disabled(!isMacOS26OrLater)`
   - Keep the macOS 26 availability check and caption text
   - Remove all `TranscriptClassifier` references
   - Simplify `.frame(width:height:)` — remove the conditional height
6. [ ] Remove the dead `resolveHierarchy(for:)` method from
   `AppleScriptNotesService.swift` — Task 0 removed it from the protocol, this is
   cleanup of the now-unused implementation
7. [ ] Remove all `resolveHierarchy` test methods from
   `UtterdTests/NotesServiceListingTests.swift` (4 tests: `resolveHierarchyTopLevel`,
   `resolveHierarchyNested`, `resolveHierarchyDeep`,
   `resolveHierarchyUnknownContainerStopsAtRoot`). Update the `@Suite` name from
   `"AppleScriptNotesService.listFolders and resolveHierarchy"` to
   `"AppleScriptNotesService.listFolders"`. Also remove the
   `resolveHierarchyContainsFolderItself` test from
   `UtterdTests/AppleScriptNotesServiceIntegrationTests.swift`. Remove the dead
   `resolveHierarchy` stub from `MockNotesServiceForSettings` in
   `UtterdTests/SettingsRoutingModelTests.swift`
8. [ ] Run `xcodebuild -scheme Utterd -destination 'platform=macOS' test` to verify all
   tests pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a fresh `UserDefaults` suite, WHEN `UserSettings` is initialized, THEN
  `summarizationEnabled == false`, `titleGenerationEnabled == false`,
  `defaultFolderName == nil`
- GIVEN `titleGenerationEnabled` set to true, WHEN a new `UserSettings` is created with
  the same defaults, THEN `titleGenerationEnabled == true`
- GIVEN defaults with stale keys `"useCustomPrompt"` (true), `"customPrompt"` ("old"),
  `"llmEnabled"` (true), WHEN `UserSettings` is initialized, THEN
  `defaults.object(forKey: "useCustomPrompt") == nil` and
  `defaults.object(forKey: "customPrompt") == nil` and
  `defaults.object(forKey: "llmEnabled") == nil`
- GIVEN `summarizationEnabled = true, titleGenerationEnabled = false,
  defaultFolderName = "Work"`, WHEN `toRoutingConfiguration()` is called, THEN result
  equals `RoutingConfiguration(summarizationEnabled: true, titleGenerationEnabled: false,
  defaultFolderName: "Work")`
- GIVEN `SettingsView.swift` and `UserSettings.swift`, WHEN searching for
  `TranscriptClassifier`, `useCustomPrompt`, `customPrompt`, `autoRoute`, `llmEnabled`,
  THEN zero matches

**Do NOT:**
- Modify `NoteRoutingPipelineStage.swift` — that is Tasks 1–3
- Modify `SettingsRoutingModel.swift` — the folder picker works unchanged
- Modify `AppDelegate.swift` — it works unchanged (same `readRoutingConfiguration()` call)
- Add feature flags or migration UI for removed settings
- Modify `PipelineControllerTests` — that was handled in Task 1

---

### Task 5: Integration Tests + Documentation Updates

**Blocked By:** Task 3, Task 4

**Relevant Files:**
- `UtterdTests/LLMIntegrationTests.swift` ← update (add 2 tests)
- `spec.md` ← update
- `CLAUDE.md` ← update

**Context to Read First:**
- `UtterdTests/LLMIntegrationTests.swift` — existing integration test pattern: uses
  `requireModelAccess()` guard, `.tags(.integration)` suite tag, asserts on structural
  properties (non-empty, format, length) not exact content
- `UtterdTests/IntegrationTestHelpers.swift` — `requireModelAccess()` helper that
  creates a `FoundationModelLLMService` and makes a probe call
- `spec.md` — current spec with routing/classification references to update:
  architecture diagram says `[LLM: classify]`, data flow mentions folder classification
- `CLAUDE.md` — project identity says "uses a language model to pick the right Notes
  folder (summarization is supported but not yet enabled)"

**Steps:**

1. [ ] Write failing integration tests in `LLMIntegrationTests.swift`:
   - Title generation test: call `FoundationModelLLMService.generate()` with a system
     prompt instructing title generation and a user prompt with a transcript about a
     specific topic (e.g., buying groceries). Assert response is non-empty, under 100
     characters, and does NOT match the regex `^Voice Memo \d{4}-\d{2}-\d{2}` (i.e., is
     not a date-based fallback)
   - Summarization quality test: create an `IterativeRefineSummarizer` with a real
     `FoundationModelLLMService`. Call `summarize()` with a transcript of at least 3,500
     words (to guarantee progressive chunking is exercised — the production budget's
     `availableForContent` is ~2,800 words) and a standard context budget. Assert the
     summary is non-empty and at most 50% of the original character count
   - Remove the classification-format test (`generateProducesMultiLineOutput`) —
     classification is no longer part of the pipeline
2. [ ] Run `xcodebuild -scheme Utterd -destination 'platform=macOS' test` to verify
   integration tests pass (may be skipped if Foundation Model is not available)
3. [ ] Update `spec.md`:
   - Architecture Summary diagram: change `[LLM: classify]` to
     `[LLM: summarize/title]`
   - Architecture Summary text: replace "folder classification" with "optional
     summarization and title generation"
   - Data flow paragraph: replace "transcript classified into a Notes folder by on-device
     LLM" with "transcript optionally summarized and titled by on-device LLM"
   - Architecture Decisions table: update the LLM row to say "LLM for optional
     summarization and title generation, not folder classification"
   - Integration Points table: update Foundation Model purpose to "On-device LLM for
     optional summarization and title generation"
   - Known Gotchas: update "App is partially implemented" — remove routing mode and
     custom prompt mentions, describe toggle-based summarization and title generation
4. [ ] Update `CLAUDE.md`:
   - Project Identity: replace "uses a language model to pick the right Notes folder
     (summarization is supported but not yet enabled)" with "optionally uses an on-device
     language model to summarize transcripts and generate descriptive titles"
5. [ ] Run full build + test: `xcodebuild -scheme Utterd -destination 'platform=macOS'
   build test` to verify SC-1
6. [ ] Verify SC-3: search all `.swift` files for `TranscriptClassifier`,
   `NoteClassificationResult`, `RoutingMode`, `FolderHierarchyEntry`,
   `buildFolderHierarchy`, `autoRoute`, `customPrompt`, `useCustomPrompt` — zero matches
   excluding `docs/plans/` files

**Acceptance Criteria:**

- GIVEN a transcript about buying groceries, WHEN the title generation integration test
  runs with a real Foundation Model, THEN the response is non-empty, under 100 characters,
  and does not match `^Voice Memo \d{4}-\d{2}-\d{2}`
- GIVEN a transcript of at least 3,500 words, WHEN the summarization integration test
  runs with a real `IterativeRefineSummarizer`, THEN the summary is non-empty and at most
  50% of the original character count
- GIVEN the updated `spec.md`, WHEN searching for `classify`, `classification`,
  `folder routing`, `custom prompt`, THEN zero matches (only summarization and title
  generation described)
- GIVEN the updated `CLAUDE.md`, WHEN reading the Project Identity section, THEN it
  describes toggle-based summarization and title generation, not folder routing
- GIVEN `xcodebuild -scheme Utterd -destination 'platform=macOS' build test`, WHEN run,
  THEN exit code is 0 with zero test failures

**Do NOT:**
- Modify any Swift source files other than `LLMIntegrationTests.swift` — all production
  code changes were completed in Tasks 0–4
- Restructure `spec.md` — only update content to remove routing references and describe
  the new toggle-based approach
- Remove architecture decision table entries — update their text
- Add new sections to `spec.md` or `CLAUDE.md`
