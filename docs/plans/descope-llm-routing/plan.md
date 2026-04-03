# Descope LLM Routing

**Status:** Approved
**Created:** 2026-04-02
**Updated:** 2026-04-02

---

## Why This Exists

The project currently uses an on-device LLM to classify voice memo transcripts into
Apple Notes folders. This folder-routing feature adds significant complexity — a
transcript classifier, folder hierarchy walker, custom prompt system, multi-mode
routing configuration — for a capability that is being cut from v1. The codebase is
heading toward open-source, and the routing machinery creates cognitive load for
anyone reading or contributing to the code.

---

## What We Are Building

Voice memos will be saved to the user's default Notes folder without any folder
routing logic. Two opt-in toggles — summarization and title generation — let users
choose whether the LLM processes their notes. When both are off, no LLM is involved
at all. All folder-routing code is deleted.

1. **Summarization** (toggle, default off): When enabled, all transcripts are
   summarized before being used as the note body. When disabled, the full
   transcript is the note body.

2. **Title Generation** (toggle, default off): When enabled, the LLM generates a
   descriptive title from the transcript content. When disabled, titles use a
   date-based fallback (e.g., "Voice Memo 2026-04-02 14:30").

---

## User Stories

### US-01: No LLM involvement

As a user with both toggles off, when I record a voice memo, the full transcript
appears as a note in my default folder with a date-based title.

- [ ] AC-01.1: GIVEN both summarization and title generation are toggled off, WHEN a
  voice memo is processed, THEN no LLM calls are made, the note body is the full
  transcript, and the title is date-based.

### US-02: Summarized notes

As a user with summarization on, when I record a voice memo, the note body is a
concise summary instead of the raw transcript.

- [ ] AC-02.1: GIVEN summarization is on and the transcript is short (fits within the
  context budget), WHEN a voice memo is processed, THEN the transcript is passed to
  the summarizer and the summarizer's output is used as the note body.
- [ ] AC-02.2: GIVEN summarization is on and the transcript is long (exceeds the
  context budget), WHEN a voice memo is processed, THEN the note body is a condensed
  summary shorter than the original transcript. The full transcript is not used as
  the note body.
- [ ] AC-02.3: GIVEN summarization is on and the transcript is empty, WHEN a voice
  memo is processed, THEN the note body is empty and no summarization LLM call is
  made.
- [ ] AC-02.4: GIVEN summarization is on and the summarizer returns an empty string,
  WHEN a voice memo is processed, THEN the note body falls back to the full
  transcript.

### US-03: Descriptive titles

As a user with title generation on, when I record a voice memo, the note has a
descriptive title derived from the content.

- [ ] AC-03.1: GIVEN title generation is on and the transcript has more than 2,000
  words, WHEN a voice memo is processed, THEN the LLM title generation call receives
  exactly the first 2,000 words of the original (pre-summarization) transcript.
- [ ] AC-03.2: GIVEN title generation is on, WHEN a voice memo is processed, THEN
  the LLM-returned title (after sanitization) is used as the note title.
- [ ] AC-03.3: GIVEN title generation is on but the transcript is empty, WHEN a voice
  memo is processed, THEN the title falls back to date-based.
- [ ] AC-03.4: GIVEN title generation is on and the LLM returns a title longer than
  100 characters, WHEN a voice memo is processed, THEN the title is truncated to 100
  characters.
- [ ] AC-03.5: GIVEN title generation is on and the LLM returns an empty string, WHEN
  a voice memo is processed, THEN the title falls back to date-based.
- [ ] AC-03.6: GIVEN title generation is on and the LLM returns a multi-line response,
  WHEN a voice memo is processed, THEN only the first non-empty line is used as the
  title.

### US-04: Both features together

As a user with both toggles on, when I record a voice memo, I get a summarized note
with a descriptive title in my default folder.

- [ ] AC-04.1: GIVEN both summarization and title generation are on, WHEN a voice memo
  is processed, THEN the note body is a summary and the title is LLM-generated. Each
  feature operates independently — summarization and title generation are separate LLM
  calls.
- [ ] AC-04.2: GIVEN both features are on and summarization succeeds but title
  generation fails, WHEN a voice memo is processed, THEN the note is created with the
  summarized body and a date-based title. The title generation failure is logged.
- [ ] AC-04.3: GIVEN both features are on and title generation succeeds but
  summarization fails, WHEN a voice memo is processed, THEN the note is created with
  the full transcript body and the LLM-generated title. The summarization failure is
  logged.

### US-05: Graceful degradation

As a user, when the LLM is unavailable or errors, my voice memos are still captured.

- [ ] AC-05.1: GIVEN summarization is on and the LLM call fails, WHEN a voice memo is
  processed, THEN the note is created with the full transcript as the body. The
  failure is logged.
- [ ] AC-05.2: GIVEN title generation is on and the LLM call fails, WHEN a voice memo
  is processed, THEN the note is created with a date-based title. The failure is
  logged.

### US-06: Settings defaults

As a user on a fresh install, neither LLM feature is active.

- [ ] AC-06.1: GIVEN a fresh install with no UserDefaults, WHEN the pipeline processes
  a memo, THEN both toggles are off and no LLM calls are made.
- [ ] AC-06.2: GIVEN macOS earlier than 26, WHEN the user opens Settings, THEN both
  LLM toggles are visible but disabled (grayed out). (Manual/visual verification
  only — OS version check cannot be mocked.)

### US-07: Clean codebase

As a contributor, the routing code is fully removed.

- [ ] AC-07.1: GIVEN the change is complete, WHEN searching Swift source files for
  `TranscriptClassifier`, `NoteClassificationResult`, `RoutingMode`,
  `FolderHierarchyEntry`, `buildFolderHierarchy`, `useCustomPrompt`, `customPrompt`,
  or `autoRoute`, THEN zero matches are found (excluding plan/doc files).

---

## Scope

### In

- Delete `TranscriptClassifier`, `NoteClassificationResult`, `RoutingMode`,
  `FolderHierarchyBuilder` (the `buildFolderHierarchy` free function and
  `FolderHierarchyEntry` struct)
- Delete or rewrite all tests that exercise folder classification
- Simplify `RoutingConfiguration`: replace `LLMApproach` enum with two booleans
  (`summarizationEnabled`, `titleGenerationEnabled`) plus `defaultFolderName`
- Rewrite `NoteRoutingPipelineStage.routeCore()`: always create note in default
  folder; optionally summarize body; optionally generate title
- Add title generation: a new LLM call that receives the first 2,000 words of the
  original transcript and returns a short title
- Simplify `UserSettings`: remove `useCustomPrompt` and `customPrompt` properties;
  add `titleGenerationEnabled`; remove stale `customPrompt` and `useCustomPrompt`
  UserDefaults keys
- Simplify `SettingsView`: remove routing mode picker, custom prompt editor, and
  "Reset to Default" button; add title generation toggle; both toggles disabled
  on macOS < 26
- Resolve default folder using a flat `listFolders(in: nil)` call instead of
  walking the full hierarchy (the `FolderHierarchyCache` actor and
  `buildFolderHierarchy` call are removed)
- Update `spec.md` and `CLAUDE.md` to reflect the new architecture
- Add integration test: given a transcript about a specific topic, the on-device
  LLM produces a title that is non-empty, under 100 characters, and does not
  match the date-based fallback format
- Add integration test: given a transcript of at least 200 words, the on-device
  LLM produces a summary that is non-empty and at most 50% of the original
  character count

### Out

- User-supplied LLM instructions / prompt customization (deferred post-v1)
- Remote LLM provider support
- Folder routing or any LLM-based folder selection
- Changing the default folder picker behavior (stays as-is)
- Progressive summarization for title generation (titles use first 2K words only)

---

## Out of Scope (Clarification)

- **User-supplied LLM instructions**: Discussed during planning as a way to let
  users customize how the LLM transforms notes (e.g., "rephrase in first person").
  Deferred because it introduces complexity around long-transcript handling —
  applying instructions chunk-by-chunk is non-trivial and not worth the v1 cost.

- **Remote LLM provider support**: The `LLMService` protocol supports this
  architecturally, but no remote provider is implemented. Deferred because on-device
  processing meets the privacy-first design goal.

- **Folder routing post-v1**: The entire classification system is being removed, not
  just disabled. If folder routing is reconsidered later, it would be rebuilt from
  scratch using simpler heuristics rather than the current classifier approach.

---

## Edge Cases

- **EC-01**: Transcript is empty — both summarization and title generation should
  no-op gracefully (empty body, date-based title) regardless of toggle state.

- **EC-02**: Transcript word count equals the context budget exactly —
  summarization treats it as fitting within the budget (single-call summarization,
  no chunking). One word over triggers progressive chunking.

- **EC-03**: LLM returns an empty string for title generation — fall back to
  date-based title.

- **EC-04**: LLM returns a very long title (>100 chars) — truncate to 100
  characters, matching existing `sanitizedTitle` logic.

- **EC-05**: Default folder configured in settings no longer exists in Notes —
  fall back to system default folder (existing behavior, preserved). Default
  folder resolution uses a flat `listFolders(in: nil)` call; if the folder name
  does not match any top-level folder, the note is created in the system default.

- **EC-06**: Existing UserDefaults contain stale `customPrompt` and
  `useCustomPrompt` keys from the old routing system — these keys are removed
  from UserDefaults, ensuring no stale data persists.

- **EC-07**: Both toggles on + LLM unavailable (model not downloaded) — both
  calls fail, note created with full transcript and date-based title. Errors
  logged independently.

- **EC-08**: Title generation with a transcript under 2,000 words — the full
  transcript is passed to the LLM (no truncation needed).

- **EC-09**: Configuration is snapshotted at the start of each memo's processing.
  Toggle changes during processing take effect on the next memo, not the current
  one. (This is existing behavior via `configProvider`, preserved.)

- **EC-10**: Summarizer returns an empty string — the note body falls back to the
  full transcript rather than creating an empty note.

---

## Technical Context

- **Platform**: macOS 15+ (Sequoia), on-device LLM requires macOS 26+
- **Language**: Swift 6.2, strict concurrency (`complete`)
- **UI**: SwiftUI with `@Observable` pattern
- **LLM**: Apple Foundation Model framework (`FoundationModels`), ~4K token
  context window (~3K words)
- **Existing abstractions that survive**: `LLMService` protocol,
  `FoundationModelLLMService`, `IterativeRefineSummarizer`,
  `TranscriptSummarizer` protocol, `LLMContextBudget`, `NotesService` protocol,
  `AppleScriptNotesService`
- **Existing abstractions being removed**: `TranscriptClassifier`,
  `NoteClassificationResult`, `RoutingMode`, `FolderHierarchyEntry`,
  `buildFolderHierarchy`, `FolderHierarchyCache` (private actor inside
  `NoteRoutingPipelineStage`)
- **Test framework**: Swift Testing (`@Test`, `#expect`, `@Suite`)
- **Project generation**: XcodeGen (`project.yml`)
- **Package structure**: App target (`Utterd/`) depends on local SPM package
  (`Libraries/Sources/Core`). Deletions from `Sources/Core` automatically remove
  them from the package — no `Package.swift` changes needed.

### Title generation call design

Title generation calls `LLMService.generate()` directly from
`NoteRoutingPipelineStage`, not through a new protocol. The system prompt
instructs the model to return a single-line descriptive title (e.g., "Generate a
short descriptive title for this voice memo transcript. Return only the title,
nothing else."). The input is the first 2,000 words of the original transcript.
The response is parsed by taking the first non-empty line, sanitized (strip
newlines/null/tab), and truncated to 100 characters. Date-based fallback on
empty result. This mirrors how `TranscriptClassifier` called
`LLMService.generate()` today.

### Mock considerations for testing

The current `MockLLMService` has a single `result` property. After this change,
`NoteRoutingPipelineStage` may call `LLMService.generate()` directly for title
generation in the same `route()` call where `MockTranscriptSummarizer` handles
summarization. Since summarization goes through the `TranscriptSummarizer`
protocol (separately mockable), the single-result `MockLLMService` remains
sufficient for title generation tests — it is only called once per `route()`
for title generation when summarization uses its own mock.

### Behavior change: summarization scope

Previously, summarization only activated when the transcript exceeded the context
budget — short transcripts were passed to the classifier verbatim. In the new
pipeline, when summarization is toggled on, ALL transcripts are summarized: short
ones via a single LLM call, long ones via progressive chunking. The existing test
`routeAndSummarizeModeDoesNotSummarizeShortTranscript` will be rewritten to
reflect this change.

### Key files affected

| File | Action |
|------|--------|
| `Libraries/Sources/Core/TranscriptClassifier.swift` | Delete |
| `Libraries/Sources/Core/NoteClassificationResult.swift` | Delete |
| `Libraries/Sources/Core/RoutingMode.swift` | Delete |
| `Libraries/Sources/Core/FolderHierarchyBuilder.swift` | Delete |
| `Libraries/Sources/Core/RoutingConfiguration.swift` | Rewrite |
| `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` | Rewrite |
| `Utterd/Core/UserSettings.swift` | Rewrite |
| `Utterd/Features/Settings/SettingsView.swift` | Rewrite |
| `Utterd/App/AppDelegate.swift` | Update (simplify stage construction) |
| `Libraries/Tests/CoreTests/TranscriptClassifierTests.swift` | Delete |
| `Libraries/Tests/CoreTests/FolderHierarchyBuilderTests.swift` | Delete |
| `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` | Rewrite |
| `UtterdTests/TranscriptClassifierIntegrationTests.swift` | Delete |
| `UtterdTests/SettingsLLMSectionTests.swift` | Rewrite |
| `UtterdTests/UserSettingsTests.swift` | Update |
| `UtterdTests/LLMIntegrationTests.swift` | Update (add title gen test) |
| `Libraries/Tests/CoreTests/PipelineControllerTests.swift` | Update (new config shape) |
| `spec.md` | Update |
| `CLAUDE.md` | Update |

### Task dependency chain

The following ordering must be respected during implementation:
1. `RoutingConfiguration` rewrite (new shape) — must come first
2. `UserSettings` rewrite — depends on new `RoutingConfiguration`
3. `NoteRoutingPipelineStage` rewrite — depends on new `RoutingConfiguration`
4. `SettingsView` rewrite — depends on new `UserSettings`
5. `AppDelegate` update — depends on new `NoteRoutingPipelineStage`
6. Tests — depend on all production code changes
7. Doc updates — depend on final code shape

### Unit test matrix for rewritten NoteRoutingPipelineStageTests

The current 22-test suite is replaced with tests covering the new toggle-based
configuration. Key scenarios:

| # | Summarization | Title Gen | Transcript | Expected behavior |
|---|---------------|-----------|------------|-------------------|
| 1 | off | off | normal | No LLM calls, full transcript body, date title |
| 2 | on | off | short | Summarizer called, summary body, date title |
| 3 | on | off | long | Progressive summarization, summary body, date title |
| 4 | off | on | normal | LLM called for title, full transcript body |
| 5 | off | on | >2K words | LLM receives first 2K words, full transcript body |
| 6 | on | on | normal | Both called independently, summary body, LLM title |
| 7 | off | off | empty | No LLM calls, empty body, date title |
| 8 | on | off | empty | No summarizer call, empty body, date title |
| 9 | off | on | empty | No LLM title call, empty body, date title |
| 10 | on | off | — | Summarizer fails → full transcript body, error logged |
| 11 | off | on | — | Title LLM fails → date title, error logged |
| 12 | on | on | — | Summarize succeeds, title fails → summary body, date title |
| 13 | on | on | — | Title succeeds, summarize fails → full body, LLM title |
| 14 | off | on | — | LLM returns empty title → date fallback |
| 15 | off | on | — | LLM returns >100 char title → truncated |
| 16 | off | on | — | LLM returns multi-line → first line used |
| 17 | on | off | — | Summarizer returns empty → full transcript fallback |
| 18 | — | — | — | Default folder resolution: name matches → that folder |
| 19 | — | — | — | Default folder resolution: name not found → system default |
| 20 | — | — | — | Default folder fetch fails → system default |
| 21 | — | — | — | markProcessed + onComplete run exactly once (success) |
| 22 | — | — | — | markProcessed + onComplete run exactly once (error) |

---

## Dependencies & Assumptions

### Dependencies
- `spec.md` — project spec, must be updated to remove routing references
- `CLAUDE.md` — project instructions, must be updated to reflect new architecture

### Assumptions
- The on-device Foundation Model context window is approximately 3,000 words
  (~4K tokens). This drives the 2,000-word truncation limit for title generation
  input, leaving headroom for the system prompt and response.
- The 100-character title truncation cap matches the existing `sanitizedTitle`
  logic in `NoteRoutingPipelineStage` and is appropriate for Apple Notes titles.
- The 2,000-word title input ceiling and 100-character title output cap were
  explicitly decided by the user during the planning interview.
- `FolderHierarchyCache` is a private actor inside `NoteRoutingPipelineStage` and
  can be removed without affecting any external consumers.

---

## Success Criteria

- **SC-1**: `xcodebuild -scheme Utterd -destination 'platform=macOS' build test`
  passes with zero failures
- **SC-2**: `cd Libraries && swift test` passes with zero failures
- **SC-3**: Grep for `TranscriptClassifier`, `NoteClassificationResult`,
  `RoutingMode`, `FolderHierarchyEntry`, `buildFolderHierarchy`, `autoRoute`,
  `customPrompt`, `useCustomPrompt` returns zero hits in Swift source files
  (excluding plan/doc files)

---

## Open Questions

- [x] **Should the LLM generate titles?** Decision: Yes, as an independent toggle
  (default off). The LLM receives the first 2,000 words of the original
  transcript. Reasoning: Titles add value but shouldn't be required; 2K words
  fits comfortably in the context window without progressive summarization.

- [x] **How should summarization + title generation compose?** Decision: They are
  separate, independent LLM calls. Summarization operates on the body;
  title generation operates on the original transcript (first 2K words).
  Reasoning: Keeps features independent and testable in isolation.

- [x] **Should there be a master LLM toggle?** Decision: No. Each feature has
  its own toggle. When all are off, no LLM is used. Reasoning: Eliminates
  the "enabled but nothing to do" invalid state entirely.

- [x] **Should short transcripts be summarized when the toggle is on?**
  Decision: Yes. All transcripts are summarized when the toggle is on.
  Reasoning: The user opted into summarization; the feature should work
  consistently regardless of transcript length.
