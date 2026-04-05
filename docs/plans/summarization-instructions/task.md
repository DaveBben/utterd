# Summarization Instructions — Task Breakdown

**Plan**: docs/plans/summarization-instructions/plan.md
**Date**: 2026-04-05
**Status**: In Progress

---

## Key Decisions

- **Instructions flow per-call, not at init**: `TranscriptSummarizer.summarize` gains an `instructions: String?` parameter. This matches the existing `configProvider` pattern — settings changes take effect on the next memo without reconstructing the summarizer. Alternative (inject at init) rejected because it would require rebuilding the summarizer whenever the user edits instructions.

- **Budget adjustment lives in the summarizer**: `IterativeRefineSummarizer` owns both the system prompt construction and the budget adjustment. When instructions are present, it computes `adjustedOverhead = baseOverhead + instructionWordCount` internally and creates a new `LLMContextBudget` before chunking. This keeps budget math co-located with prompt construction. Alternative (caller adjusts budget) rejected because it leaks prompt implementation details to the caller.

- **Whitespace normalization**: Instructions are trimmed (`trimmingCharacters(in: .whitespacesAndNewlines)`) and treated as empty if the result is empty. This happens at the summarizer level, not in UserSettings — the raw value is stored as-is, normalization is a prompt-construction concern.

- **Word counting via shared helper**: Both the UI 300-word limit and the budget adjustment use a shared `wordCount(_:)` function in `Libraries/Sources/Core/` that calls `split(whereSeparator: \.isWhitespace).count`. This matches the summarizer's existing word-splitting behavior and ensures consistency between UI enforcement and budget calculation. A single implementation prevents the two from drifting apart.

- **No AppDelegate changes**: The existing `configProvider` closure calls `UserSettings.readRoutingConfiguration()`, which will automatically include the new `summarizationInstructions` field after Task 1. The base `contextBudget` (200-word overhead) remains unchanged — the summarizer adjusts it internally per Task 2.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-1.1: Instructions input visible when summarization enabled | Task 4 |
| AC-1.2: 300-word limit enforced in UI | Task 4 |
| AC-1.3: Instructions persist across restarts; fresh install = nil | Task 1 |
| AC-1.4: System prompt contains base + instructions when present; equals base when empty | Task 2, Task 3 |
| AC-1.5: Budget overhead increases by instruction word count | Task 2 |
| AC-2.1: Empty instructions → identical prompt to today | Task 2 |
| AC-2.2: Toggle off hides field, toggle on restores content | Task 4 |
| EC-1: Whitespace-only → treated as empty | Task 2 |
| EC-2: Exactly 300 words accepted | Task 4 |
| EC-3: Instructions change mid-processing → next memo picks up | Task 3 (covered by existing configProvider snapshot pattern; verified by per-call config read in Task 3 tests) |
| EC-4: Very short instructions (1-2 words) valid | Task 2 |
| EC-5: Budget impact of long instructions | Task 2 |

---

## Tasks

### Task 0: Define Contracts & Interfaces

**Relevant Files:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` ← modify
- `Libraries/Sources/Core/TranscriptSummarizer.swift` ← modify
- `Libraries/Sources/Core/WordCount.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptSummarizer.swift` ← modify

**Context to Read First:**
- `Libraries/Sources/Core/RoutingConfiguration.swift` — current struct with 4 fields and memberwise init; new field must preserve `Equatable` conformance and default to `nil`
- `Libraries/Sources/Core/TranscriptSummarizer.swift` — single-method protocol; understand current signature before adding parameter
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptSummarizer.swift` — mock records `(transcript, contextBudget)` tuples; must also record `instructions`

**Steps:**
1. [ ] Add `public var summarizationInstructions: String?` to `RoutingConfiguration`, defaulting to `nil` in `init`
2. [ ] Add `instructions: String?` parameter (defaulting to `nil`) to `TranscriptSummarizer.summarize`
3. [ ] Create `Libraries/Sources/Core/WordCount.swift` with `public func wordCount(_ text: String) -> Int` that returns `text.split(whereSeparator: \.isWhitespace).count`
4. [ ] Update `MockTranscriptSummarizer`: change `calls` tuple to include `instructions: String?`, update `summarize` to record it
5. [ ] Update `IterativeRefineSummarizer.summarize` signature to accept `instructions: String? = nil` and pass it through (no behavior change yet — just forward the parameter)
6. [ ] Verify compilation: `cd Libraries && swift build </dev/null 2>&1`

**Acceptance Criteria:**
- `RoutingConfiguration(summarizationInstructions: "test")` compiles and equals a copy of itself
- `RoutingConfiguration(summarizationInstructions: "a") != RoutingConfiguration(summarizationInstructions: "b")` (Equatable distinguishes values)
- `TranscriptSummarizer.summarize(transcript:contextBudget:instructions:)` compiles
- `MockTranscriptSummarizer.calls` captures the `instructions` value
- `wordCount("hello world")` returns 2

**Do NOT:**
- Add any business logic beyond the `wordCount` helper — this task defines interfaces only
- Change `LLMService` protocol — title generation is not affected
- Add migration logic to `UserSettings` — that's Task 1

---

### Task 1: UserSettings & Config Threading

**Blocked By:** Task 0

**Relevant Files:**
- `Utterd/Core/UserSettings.swift` ← modify
- `UtterdTests/UserSettingsTests.swift` ← modify
- `UtterdTests/SettingsLLMSectionTests.swift` ← modify

**Context to Read First:**
- `Utterd/Core/UserSettings.swift` — existing `@Observable` property pattern using `access(keyPath:)` / `withMutation(keyPath:)` with `UserDefaults`; follow this exact pattern for the new property. Note the `Keys` enum and `readRoutingConfiguration(from:)` static method
- `UtterdTests/UserSettingsTests.swift` — existing tests verify persistence, defaults, and `toRoutingConfiguration()` mapping; follow same test structure
- `UtterdTests/SettingsLLMSectionTests.swift` — tests `toRoutingConfiguration()` output; add a test for instructions threading

**Steps:**
1. [ ] Write failing tests:
   - `summarizationInstructions` defaults to `nil` on fresh `UserDefaults`
   - `summarizationInstructions` persists across re-init (set "Focus on action items" → new `UserSettings` instance → read back)
   - `toRoutingConfiguration()` maps `summarizationInstructions` into `RoutingConfiguration.summarizationInstructions`
   - `readRoutingConfiguration(from:)` maps the value identically
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Add `static let summarizationInstructions = "summarizationInstructions"` to `UserSettings.Keys`
4. [ ] Add `summarizationInstructions: String?` computed property using `access`/`withMutation`/`UserDefaults` pattern matching existing properties
5. [ ] Update `toRoutingConfiguration()` to pass `summarizationInstructions` to the `RoutingConfiguration` init
6. [ ] Update `readRoutingConfiguration(from:)` to read `summarizationInstructions` from `defaults` and pass to `RoutingConfiguration` init
7. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**
- GIVEN a fresh `UserDefaults` suite, WHEN `UserSettings` is created, THEN `summarizationInstructions` is `nil`
- GIVEN `summarizationInstructions` is set to "Focus on action items", WHEN a new `UserSettings` is created with the same `UserDefaults`, THEN `summarizationInstructions` equals "Focus on action items"
- GIVEN `summarizationInstructions` is set, WHEN `toRoutingConfiguration()` is called, THEN the returned `RoutingConfiguration.summarizationInstructions` matches
- GIVEN `summarizationInstructions` is set in `UserDefaults`, WHEN `readRoutingConfiguration(from:)` is called, THEN the returned `RoutingConfiguration.summarizationInstructions` matches

**Do NOT:**
- Add word-count validation — that's the UI's job (Task 4)
- Trim whitespace — that's the summarizer's job (Task 2)
- Bump `migrationVersion` — the new key is additive

---

### Task 2: IterativeRefineSummarizer Instructions & Budget

**Blocked By:** Task 0

**Relevant Files:**
- `Libraries/Sources/Core/IterativeRefineSummarizer.swift` ← modify
- `Libraries/Tests/CoreTests/IterativeRefineSummarizerTests.swift` ← modify

**Context to Read First:**
- `Libraries/Sources/Core/IterativeRefineSummarizer.swift` — understand the chunking loop: system prompt is `"You are a concise summarizer. Return only the summary text."` on every chunk. `contextBudget.systemPromptOverhead` is deducted from `totalWords` to compute `availableForContent`, which determines chunk size. Instructions appended to the system prompt increase its actual word count, so `systemPromptOverhead` must increase by the instruction word count
- `Libraries/Sources/Core/LLMContextBudget.swift` — `init` has a precondition: `totalWords > systemPromptOverhead`. If instructions push overhead past totalWords, the budget `fatalError`s. The summarizer must guard against this
- `Libraries/Tests/CoreTests/IterativeRefineSummarizerTests.swift` — uses `SequenceMockLLMService` that captures `(systemPrompt, userPrompt)` per call; assert on `systemPrompt` content to verify instructions are appended

**Steps:**
1. [ ] Write failing tests:
   - `instructions: nil` → system prompt equals `"You are a concise summarizer. Return only the summary text."` exactly (no trailing whitespace) — assert on ALL chunks when multi-chunk
   - `instructions: ""` → system prompt identical to nil case
   - `instructions: "   \n  "` (whitespace-only) → system prompt identical to nil case
   - `instructions: "  \nFocus on action items\n  "` (leading/trailing whitespace) → system prompt equals base prompt + `"\n\n"` + `"Focus on action items"` (trimmed)
   - `instructions: "Focus on action items"` with multi-chunk transcript → system prompt contains instructions on every chunk call (assert ALL `calls[n].systemPrompt`)
   - Budget adjustment: given a specific instruction word count, verify that a transcript that was 1 chunk without instructions becomes 2+ chunks with instructions (use concrete numbers: e.g., budget with `availableForNewChunk=560` without instructions, instructions of 200 words reduce it to `availableForNewChunk` for the adjusted budget, forcing a split)
   - Budget clamping: construct a scenario where `systemPromptOverhead + instructionWordCount >= totalWords` (e.g., `totalWords=210, systemPromptOverhead=200`, instructions of 20 words). Assert: does not crash, LLM is called at least once, and the adjusted budget's `availableForContent` equals 1 (proving the clamp was used, not the original budget)
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] In `summarize`, trim instructions (`trimmingCharacters(in: .whitespacesAndNewlines)`); treat empty result as nil
4. [ ] When trimmed instructions are non-nil, compute `instructionWordCount` using `wordCount(instructions)` (the shared helper from Task 0); create adjusted budget: `LLMContextBudget(totalWords: contextBudget.totalWords, systemPromptOverhead: min(contextBudget.systemPromptOverhead + instructionWordCount, contextBudget.totalWords - 1), summaryReserveRatio: contextBudget.summaryReserveRatio)`
5. [ ] Use the adjusted budget (or original when no instructions) for all chunk-size calculations
6. [ ] Construct the system prompt: base prompt alone when no instructions; `basePrompt + "\n\n" + trimmedInstructions` when present. Use this system prompt on every LLM call in the chunking loop
7. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**
- GIVEN `instructions` is nil, WHEN `summarize` is called on a multi-chunk transcript, THEN the system prompt passed to the LLM on every chunk equals the base prompt exactly
- GIVEN `instructions` is `""` or whitespace-only, WHEN `summarize` is called, THEN the system prompt equals the base prompt exactly (no trailing whitespace or separators)
- GIVEN `instructions` is `"  \nFocus on action items\n  "`, WHEN `summarize` is called, THEN the system prompt on every chunk equals `"You are a concise summarizer. Return only the summary text.\n\nFocus on action items"` (trimmed)
- GIVEN `instructions` is `"Focus on action items"`, WHEN `summarize` is called on a multi-chunk transcript, THEN every `calls[n].systemPrompt` contains the instructions (not just the first chunk)
- GIVEN instructions of N words, WHEN `summarize` is called, THEN the budget used for chunking has `systemPromptOverhead = baseOverhead + N`, and the resulting chunk count is higher than without instructions for the same transcript
- GIVEN instructions so long they would push overhead past `totalWords`, WHEN `summarize` is called, THEN the call does not crash, the LLM is called, and the effective `availableForContent` is 1 (clamped budget, not original)

**Do NOT:**
- Change the `LLMService` protocol or `generate` method signature
- Modify title generation logic — instructions are for summarization only
- Add instructions to the user prompt — they go in the system prompt only

---

### Task 3: NoteRoutingPipelineStage Instructions Pass-Through

**Blocked By:** Task 0, Task 2

**Relevant Files:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` ← modify
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` ← modify

**Context to Read First:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` — `routeCore` reads `config = configProvider()` and calls `summarizer.summarize(transcript:contextBudget:)`. Add `instructions:` parameter from `config.summarizationInstructions`. The `contextBudget` stored property is passed as-is — the summarizer handles budget adjustment internally (Task 2)
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` — `makeStage` helper creates stages with `MockTranscriptSummarizer`; config is passed as `RoutingConfiguration`. The mock's `calls` tuple now includes `instructions` (from Task 0). Note: `MockLLMService` is used exclusively for title generation in these tests, so asserting its `systemPrompt` verifies title generation is unaffected

**Steps:**
1. [ ] Write failing tests:
   - Summarization enabled with `summarizationInstructions: "Be brief"` → `MockTranscriptSummarizer.calls[0].instructions` equals `"Be brief"`
   - Summarization enabled with `summarizationInstructions: nil` → `MockTranscriptSummarizer.calls[0].instructions` is `nil`
   - Summarization disabled with instructions set → summarizer not called (existing behavior preserved)
   - Title generation enabled with instructions set → `MockLLMService.calls[0].systemPrompt` contains only the title prompt (no summarization instructions injected)
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] In `routeCore`, update the `summarizer.summarize` call to pass `instructions: config.summarizationInstructions`
4. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**
- GIVEN summarization is enabled and `summarizationInstructions` is `"Be brief"`, WHEN a memo is processed, THEN the summarizer receives `instructions: "Be brief"`
- GIVEN summarization is enabled and `summarizationInstructions` is nil, WHEN a memo is processed, THEN the summarizer receives `instructions: nil`
- GIVEN summarization is disabled, WHEN a memo is processed, THEN the summarizer is not called regardless of instructions value
- GIVEN title generation is enabled and instructions are set, WHEN a memo is processed, THEN the LLM mock receives only the title generation system prompt (no summarization instructions)

**Do NOT:**
- Adjust the `contextBudget` in this stage — the summarizer handles that (Task 2)
- Modify `AppDelegate` — the `configProvider` closure already threads the value via `readRoutingConfiguration`
- Add instructions to title generation

---

### Task 4: Settings UI — Instructions Input

**Blocked By:** Task 1

**Note:** Tasks 2 and 3 must also be complete before end-to-end manual verification (step 8) is meaningful. The compile-time dependency is only on Task 1.

**Relevant Files:**
- `Utterd/Features/Settings/SettingsView.swift` ← modify
- `Utterd/Core/WordLimitEnforcer.swift` ← create
- `UtterdTests/WordLimitEnforcerTests.swift` ← create

**Context to Read First:**
- `Utterd/Features/Settings/SettingsView.swift` — the LLM section has summarization and title generation toggles. The input should appear below the summarization toggle, only when `settings.summarizationEnabled` is true. The form uses `.grouped` style. Frame is currently `480 x 300` and will need to grow
- `Utterd/Core/UserSettings.swift` — after Task 1, has `summarizationInstructions: String?` property; bind via `@Bindable var settings`
- `Libraries/Sources/Core/WordCount.swift` — the shared `wordCount(_:)` function from Task 0; import `Core` to use it

**Steps:**
1. [ ] Write failing tests in `UtterdTests/WordLimitEnforcerTests.swift`:
   - `enforceWordLimit("", limit: 300)` returns `""`
   - `enforceWordLimit("one two three", limit: 300)` returns `"one two three"` (under limit, unchanged)
   - `enforceWordLimit` with exactly 300 words returns all 300 words
   - `enforceWordLimit` with 301 words returns first 300 words joined by spaces
   - `enforceWordLimit("  spaced  out  ", limit: 300)` returns `"  spaced  out  "` (under limit, preserved as-is including whitespace)
   - `enforceWordLimit` with 301 words where input has mixed whitespace (tabs, newlines) → truncated to 300 words, rejoined with spaces
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Create `Utterd/Core/WordLimitEnforcer.swift` with `func enforceWordLimit(_ text: String, limit: Int) -> String`: if `wordCount(text) <= limit`, return text unchanged; otherwise, return `text.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")`
4. [ ] Add the new files to `project.yml` sources if needed (they're under `Utterd/` so should be auto-included)
5. [ ] In `SettingsView`, add a `TextEditor` below the summarization toggle, wrapped in `if settings.summarizationEnabled`. Bind to `$settings.summarizationInstructions` using a custom `Binding` whose setter calls `enforceWordLimit(newValue, limit: 300)` and stores the result. Handle nil↔String conversion (empty string → nil for storage, nil → empty string for display)
6. [ ] Add a word count indicator below the field showing `"\(wordCount(text)) / 300 words"` using the shared `wordCount` helper
7. [ ] Increase the frame height to accommodate the new field (e.g., `480 x 420` or use dynamic sizing)
8. [ ] Add a label `"Summarization Instructions"` and helper text `"Guide how memos are summarized (optional)"`
9. [ ] Run tests to verify they pass (confirm GREEN state)
10. [ ] Manual verification: build the app, open Settings, toggle summarization on/off, type instructions, verify 300-word limit truncates on paste, verify content preserved across toggle, verify word counter updates

**Acceptance Criteria:**
- GIVEN summarization is enabled, WHEN the user opens settings, THEN an instructions input area is visible
- GIVEN summarization is disabled, WHEN the user opens settings, THEN the instructions input is hidden
- GIVEN the field contains 300 words, WHEN the user pastes additional text that would exceed 300 words, THEN the text is truncated to 300 words
- GIVEN instructions are entered and summarization is toggled off then on, THEN the instructions are still present
- GIVEN a fresh install, THEN the instructions field is empty
- `enforceWordLimit` with 300 words returns all words; with 301 returns first 300 (automated test)

**Do NOT:**
- Add character-level validation — only word count matters
- Add a "Reset" or "Clear" button — the user can select-all and delete
- Modify other sections of the settings view
- Implement a separate word-counting function — use the shared `wordCount` from `Core`
