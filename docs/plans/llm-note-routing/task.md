# LLM Note Routing — Task Breakdown

**Plan**: [plan.md](plan.md)
**Date**: 2026-03-31
**Status**: In Progress

---

## Key Decisions

- **LLM response format**: Line-separated plain text — folder path on line 1, title on line 2. Chosen over JSON because the Foundation Model may not reliably produce valid JSON, and line parsing is simpler and more robust. The classifier prompt explicitly instructs this format.
- **LLM protocol design**: `LLMService` protocol with `generate(systemPrompt:userPrompt:) async throws -> String` in `Libraries/Sources/Core/`, with `FoundationModelLLMService` in `Utterd/Core/`. The Foundation Model API (`LanguageModelSession`) sets instructions at session creation, not per-call. The concrete implementation creates a new session per `generate()` call with the `systemPrompt` as instructions — this is intentional because the classifier and summarizer use different system prompts, so session reuse does not apply. Follows the existing `TranscriptionService`/`SpeechAnalyzerTranscriptionService` pattern.
- **Folder hierarchy as a function, not a type**: `buildFolderHierarchy(using:)` is an async function that takes `any NotesService` and returns `[(path: String, folder: NotesFolder)]`. No need for a stateful class — hierarchy is rebuilt each time a memo is routed (folder list may change between memos). The return type pairs the dot-notation path string with the `NotesFolder` for lookup after classification. Note: this uses recursive `listFolders(in:)` calls which produces N+1 AppleScript calls; for typical user hierarchies (10-20 folders, 2-3 levels) this is acceptable. If performance is an issue, a future optimization could add a bulk-fetch method to `NotesService` (similar to how `resolveHierarchy` already fetches all folders in one call).
- **Summarizer as a standalone protocol**: `TranscriptSummarizer` protocol with a single `summarize(transcript:contextBudget:) async throws -> String` method (no `using:` parameter — the concrete implementation receives the `LLMService` at init time). This keeps the routing stage testable with a mock summarizer without needing to also provide a mock LLM.
- **Context window constant**: A named constant `LLMContextBudget` struct with `totalWords`, `systemPromptOverhead`, `summaryReserveRatio` (default 0.3), and computed `availableForContent` and `availableForNewChunk` properties. `totalWords` is a conservative proxy for the ~4096 token limit (~3K words ≈ ~4K tokens). Chunk sizing subtracts system prompt size (including folder list) dynamically rather than using a hardcoded number. `summaryReserveRatio` controls what fraction of `availableForContent` is reserved for the rolling summary in chunked summarization.
- **Stage 2 lock release**: `NoteRoutingPipelineStage` accepts an `onComplete: @Sendable () async -> Void` callback at init time (not a settable property — keeping the class immutable for `Sendable` compliance). The `route()` method calls `markProcessed` and `onComplete` after its do/catch block (not in a `defer` block, since `defer` cannot contain `await` in Swift). `PipelineController` constructs the stage once in `start()` via a factory closure, passing `{ await MainActor.run { scheduler.releaseLock() } }` as `onComplete` (the `MainActor.run` is needed because `releaseLock()` is `@MainActor`-isolated). The controller does NOT call `releaseLock()` after `route()` returns — `onComplete` is the single mechanism.
- **Stage 2 wiring**: `PipelineController` gains an optional `noteRoutingStage` dependency. When present, `onResult` delegates to it; when absent, falls back to the current "awaiting stage 2" log. This preserves backward compatibility during incremental development.
- **Routing mode enum**: `RoutingMode.routeOnly` and `.routeAndSummarize` — the enum is defined in Task 0 but only `.routeOnly` is active. The pipeline stage accepts it as a parameter so future UI work can toggle it without changing internals.
- **MockNotesService enhancement**: The existing mock returns a flat `listFoldersResult` for all calls. For recursive hierarchy testing, the mock will be enhanced to support per-parent responses via a `[String?: [NotesFolder]]` dictionary keyed by parent folder ID. Note: `parent?.id` evaluates to `nil` (type `String?`) when `parent` is `nil`, which correctly matches the nil key for root-level calls. Swift `Dictionary` supports `Optional` keys because `Optional: Hashable` when `Wrapped: Hashable`.
- **Date-based fallback title format**: When the LLM response is missing a title, use the format `"Voice Memo yyyy-MM-dd HH:mm"` in UTC timezone (e.g., "Voice Memo 2026-03-31 14:30"). The classifier and routing stage accept a `now: Date` parameter for deterministic testing. The `DateFormatter` uses format string `"'Voice Memo' yyyy-MM-dd HH:mm"` with `timeZone = .gmt`.

---

## Open Questions

None — all decisions resolved during planning.

---

## Requirement Traceability

| Plan Requirement | Task(s) |
|-----------------|---------|
| AC-01.1 (short transcript routing) | Task 3, Task 5 |
| AC-01.2 (unrecognized folder → default) | Task 3 |
| AC-01.3 (mark processed + release lock) | Task 5 |
| AC-01.4 (empty transcript → default folder) | Task 5 |
| AC-01.5 (note creation error handling) | Task 5 |
| AC-01.6 (case-insensitive + whitespace trimming) | Task 3 |
| AC-01.7 (empty folder hierarchy → default) | Task 5 |
| AC-01.8 (missing title → date fallback) | Task 3, Task 5 |
| AC-02.1 (long transcript summarized for classification) | Task 4, Task 5 |
| AC-02.2 (note body = full transcript, not summary) | Task 5 |
| AC-02.3 (no prompt exceeds context window) | Task 4 |
| AC-03.1 (route-only mode → full transcript body) | Task 5 |
| AC-03.2 (route-and-summarize mode → summary body) | Task 5 |
| AC-03.3 (classification prompt identical in both modes) | Task 5 |
| AC-04.1 (end-to-end flow from transcription to note) | Task 6 |
| AC-04.2 (lock release on success or failure) | Task 5, Task 6 |
| AC-04.3 (model unavailable → mark processed, no retry) | Task 5 |
| Edge: empty transcript | Task 5 |
| Edge: unrecognized folder name | Task 3 |
| Edge: whitespace/casing in folder match | Task 3 |
| Edge: empty folder hierarchy | Task 5 |
| Edge: folder deleted between classify and create | Task 5 |
| Edge: model unavailable or errors | Task 5 |
| Edge: note creation throws error | Task 5 |
| Edge: transcript near context boundary | Task 4 |
| Edge: very short transcript | Task 3 |
| Edge: deeply nested hierarchy | Task 2 |
| Edge: folder name contains dot | Task 3 |
| Edge: model returns empty/missing title | Task 3 |
| Edge: model response unparseable | Task 3 |

---

## Tasks

### Task 0: Define Contracts & Interfaces

**Relevant Files:**
- `Libraries/Sources/Core/LLMService.swift` ← create
- `Libraries/Sources/Core/TranscriptSummarizer.swift` ← create
- `Libraries/Sources/Core/NoteClassificationResult.swift` ← create
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` ← create (protocol + public interface only)
- `Libraries/Sources/Core/RoutingMode.swift` ← create
- `Libraries/Sources/Core/LLMContextBudget.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/TranscriptionService.swift` — pattern for protocol definition (single-method service protocol with async throws)
- `Libraries/Sources/Core/TranscriptionResult.swift` — pattern for result types (struct, Sendable, Equatable)
- `Libraries/Sources/Core/NotesFolder.swift` — the `NotesFolder` type used by hierarchy and classification
- `Libraries/Sources/Core/NoteCreationResult.swift` — pattern for result enums

**Steps:**

1. [ ] Define `LLMService` protocol with `generate(systemPrompt:userPrompt:) async throws -> String` — the system prompt is passed per-call because each use site (classifier, summarizer) has a different system prompt
2. [ ] Define `RoutingMode` enum with `.routeOnly` and `.routeAndSummarize` cases, conforming to `Sendable`
3. [ ] Define `LLMContextBudget` struct with `totalWords: Int`, `systemPromptOverhead: Int`, `summaryReserveRatio: Double` (default 0.3), computed `availableForContent: Int` (totalWords - systemPromptOverhead), and computed `availableForNewChunk: Int` (availableForContent * (1 - summaryReserveRatio)). Conform to `Sendable`
4. [ ] Define `NoteClassificationResult` struct with `folderPath: String?` (nil = general/default) and `title: String` fields, conforming to `Sendable` and `Equatable`
5. [ ] Define `TranscriptSummarizer` protocol with `summarize(transcript:contextBudget:) async throws -> String` — no `using:` parameter; the concrete implementation receives the `LLMService` at its own init
6. [ ] Define `NoteRoutingPipelineStage` as a `public final class: Sendable` with `init` accepting: `notesService: any NotesService`, `llmService: any LLMService`, `summarizer: any TranscriptSummarizer`, `store: any MemoStore`, `logger: any WatcherLogger`, `mode: RoutingMode`, `contextBudget: LLMContextBudget`, `onComplete: @Sendable () async -> Void`. All stored as `let` properties (class is immutable after init). Define `public func route(_ result: TranscriptionResult) async` as a method stub (body left empty — implemented in Task 5)
7. [ ] Verify all types compile: `cd Libraries && swift build </dev/null`

**Acceptance Criteria:**

- GIVEN all contract files, WHEN compiled, THEN no type errors or warnings exist
- GIVEN the `LLMService` protocol, WHEN read by a developer, THEN the input (system + user prompts) and output (plain string) are unambiguous
- GIVEN `NoteClassificationResult`, WHEN `folderPath` is nil, THEN the consuming code knows to use the default folder
- GIVEN `NoteRoutingPipelineStage.init`, WHEN read by a developer, THEN all dependencies and their purposes are clear from the parameter names and types

**Do NOT:**
- Implement any business logic — only define types, protocols, and the stage's public interface
- Add Foundation Model framework imports — the concrete implementation is in Task 1
- Define folder hierarchy types — hierarchy building is a function returning tuples, not a custom type

---

### Task 1: LLM Service — Foundation Model Implementation & Test Mocks

**Blocked By:** Task 0

**Relevant Files:**
- `Utterd/Core/FoundationModelLLMService.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/MockLLMService.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptSummarizer.swift` ← create
- `Libraries/Tests/CoreTests/MockLLMServiceTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/LLMService.swift` — the protocol this task implements (defined in Task 0)
- `Libraries/Sources/Core/TranscriptSummarizer.swift` — the summarizer protocol; this task creates its mock (defined in Task 0)
- `Utterd/Core/SpeechAnalyzerTranscriptionService.swift` — pattern for macOS 26+ `@available` gating and Foundation Model framework usage
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptionService.swift` — pattern for mock: `@unchecked Sendable`, `nonisolated(unsafe)` properties, configurable result/error

**Steps:**

1. [ ] Write failing tests for mock infrastructure validation: test that `MockLLMService` returns a configured response and records prompts, test that `MockTranscriptSummarizer` returns a configured summary and records calls. These tests validate the test infrastructure that Tasks 3-5 depend on
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `MockLLMService` following the existing mock pattern: `nonisolated(unsafe) var result: String = ""`, `nonisolated(unsafe) var error: Error?`, `nonisolated(unsafe) var calls: [(systemPrompt: String, userPrompt: String)] = []`
4. [ ] Implement `MockTranscriptSummarizer` following the same pattern: `nonisolated(unsafe) var result: String = ""`, `nonisolated(unsafe) var error: Error?`, `nonisolated(unsafe) var calls: [(transcript: String, contextBudget: LLMContextBudget)] = []`
5. [ ] Implement `FoundationModelLLMService` gated with `@available(macOS 26, *)`: import FoundationModels, in `generate()` create a `LanguageModelSession(instructions: systemPrompt)`, call `respond(to: userPrompt)`, return the response string
6. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a `MockLLMService` configured with result "hello", WHEN `generate(systemPrompt: "sys", userPrompt: "usr")` is called, THEN it returns "hello" and `calls` contains `[("sys", "usr")]`
- GIVEN a `MockLLMService` configured with an error, WHEN `generate` is called, THEN it throws the configured error
- GIVEN a `MockTranscriptSummarizer` configured with result "summary", WHEN `summarize(transcript: "long text", contextBudget: budget)` is called, THEN it returns "summary" and `calls` contains the transcript and budget
- GIVEN `FoundationModelLLMService`, WHEN compiled on macOS 26+, THEN it compiles without errors (runtime test requires actual device with Foundation Model support)

**Do NOT:**
- Test the actual Foundation Model responses — that requires runtime on a macOS 26 device; only test the mocks and verify compilation of the concrete implementation
- Add retry logic — spec says each memo is attempted once
- Add streaming support — the response is consumed as a complete string
- Add session caching or reuse — each `generate()` call creates a fresh session because callers use different system prompts

---

### Task 2: Folder Hierarchy Builder

**Relevant Files:**
- `Libraries/Sources/Core/FolderHierarchyBuilder.swift` ← create
- `Libraries/Tests/CoreTests/FolderHierarchyBuilderTests.swift` ← create
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` ← modify (enhance for per-parent responses)

**Context to Read First:**
- `Libraries/Sources/Core/NotesService.swift` — `listFolders(in:)` returns immediate children only; this task builds recursive traversal
- `Libraries/Sources/Core/NotesFolder.swift` — `NotesFolder` has `id`, `name`, `containerID`; equality is by `id` only
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` — current mock returns flat `listFoldersResult` for all calls; needs per-parent support for hierarchy tests

**Steps:**

1. [ ] Write failing tests for `buildFolderHierarchy(using:)`:
   - Test with a flat hierarchy (3 top-level folders, no children) → returns 3 entries with simple names, sorted alphabetically
   - Test with nested hierarchy (finance → home, taxes; personal → health) → returns entries with dot-notation paths (e.g., "finance.home"), sorted alphabetically
   - Test with deeply nested hierarchy (3+ levels) → dot notation works at any depth
   - Test with empty folder list (no top-level folders) → returns empty array
   - Test sort order: given top-level folders ["personal", "finance"] (in that order from NotesService), result paths are sorted alphabetically: ["finance", "personal"]
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Enhance `MockNotesService`: add `nonisolated(unsafe) var listFoldersByParent: [String?: [NotesFolder]] = [:]` dictionary keyed by parent folder ID (nil key = root). In `listFolders(in:)`, use `listFoldersByParent[parent?.id]` — note that `parent?.id` evaluates to `nil` (type `String?`) when `parent` is `nil`, which correctly matches the nil key for root-level calls (Swift `Optional` conforms to `Hashable`). If the key is present, return its value; otherwise fall back to existing `listFoldersResult`
4. [ ] Implement `buildFolderHierarchy(using:)` as a public async function: call `listFolders(in: nil)` to get top-level folders, then for each folder recursively call `listFolders(in: folder)` to discover children, building dot-notation paths by concatenating parent path + "." + child name. Return `[(path: String, folder: NotesFolder)]` sorted alphabetically by path
5. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a `NotesService` with top-level folders ["finance", "personal"], WHEN `buildFolderHierarchy` is called, THEN it returns entries with paths ["finance", "personal"]
- GIVEN a `NotesService` with "finance" containing children ["home", "taxes"], WHEN `buildFolderHierarchy` is called, THEN it returns entries including "finance", "finance.home", "finance.taxes"
- GIVEN a 3-level hierarchy (work → projects → utterd), WHEN `buildFolderHierarchy` is called, THEN it returns "work", "work.projects", "work.projects.utterd"
- GIVEN a `NotesService` that returns no top-level folders, WHEN `buildFolderHierarchy` is called, THEN it returns an empty array
- GIVEN top-level folders ["personal", "finance"] (in that order from NotesService), WHEN `buildFolderHierarchy` is called, THEN result paths are sorted alphabetically: ["finance", "personal"]

**Do NOT:**
- Cache the hierarchy — it is rebuilt each time a memo is routed
- Create a custom `FolderNode` tree type — the flat `[(path, folder)]` array is sufficient for the system prompt and for folder matching
- Handle `listFolders` errors — let them propagate to the caller (the routing stage handles errors)
- Modify `NotesFolder` or `NotesService` protocol — work with existing types

---

### Task 3: Transcript Classifier (Prompt + Response Parsing)

**Blocked By:** Task 0, Task 1

**Relevant Files:**
- `Libraries/Sources/Core/TranscriptClassifier.swift` ← create
- `Libraries/Tests/CoreTests/TranscriptClassifierTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/LLMService.swift` — protocol used to send classification prompts (Task 0)
- `Libraries/Sources/Core/NoteClassificationResult.swift` — result type: `folderPath` (nil = default) and `title` (Task 0)
- `Libraries/Sources/Core/NotesFolder.swift` — `NotesFolder` type used in the hierarchy entries
- `Libraries/Tests/CoreTests/Mocks/MockLLMService.swift` — mock for controlling LLM responses in tests (Task 1)

**Steps:**

1. [ ] Write failing tests for `TranscriptClassifier.classify(transcript:hierarchy:using:)`:
   - Test happy path: LLM returns "finance.home\nGrocery list for March" → result has `folderPath: "finance.home"`, `title: "Grocery list for March"`
   - Test "GENERAL NOTES" response: LLM returns "GENERAL NOTES\nRandom thoughts" → result has `folderPath: nil`, `title: "Random thoughts"`
   - Test unrecognized folder: LLM returns "nonexistent.folder\nSome title" → result has `folderPath: nil` (treated as general)
   - Test case-insensitive + whitespace: LLM returns " Finance.Home \n  Title  " → result has `folderPath: "finance.home"` (matched against hierarchy)
   - Test missing title (single line, no title): LLM returns "finance.home" → result has `folderPath: "finance.home"`, title is date-based fallback
   - Test completely unparseable response (empty string): result has `folderPath: nil`, title is date-based fallback
   - Test that the system prompt sent to the LLM contains the folder hierarchy in dot notation and instructs the expected response format
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `TranscriptClassifier` as a struct with a `classify(transcript:hierarchy:using:now:)` method. Build the system prompt: instruct the model to respond with the folder path on line 1 and a short title on line 2, list the available folders from `hierarchy` in dot notation, and include "GENERAL NOTES" as the fallback option
4. [ ] Implement response parsing: split the LLM response by newline, extract folder path from line 1 (trimmed, lowercased), title from line 2 (trimmed). If line 1 matches a known hierarchy path (case-insensitive comparison), use it; otherwise treat as "GENERAL NOTES" (set `folderPath` to nil). If title is empty or missing, generate a date-based fallback using the `now` parameter
5. [ ] Implement folder matching: compare the trimmed, lowercased model response against the lowercased hierarchy paths. Return the matching path as-is from the hierarchy (preserving original casing for display) or nil if no match
6. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a transcript and hierarchy ["finance", "finance.home", "personal"], WHEN the LLM responds "finance.home\nGrocery list", THEN result is `NoteClassificationResult(folderPath: "finance.home", title: "Grocery list")`
- GIVEN the LLM responds "GENERAL NOTES\nSome thought", WHEN classified, THEN `folderPath` is nil and `title` is "Some thought"
- GIVEN the LLM responds "nonexistent.folder\nTitle", WHEN classified against a known hierarchy, THEN `folderPath` is nil (treated as general)
- GIVEN the LLM responds " Finance.Home \n Title ", WHEN classified against hierarchy containing "finance.home", THEN `folderPath` is "finance.home" (matched case-insensitively, whitespace trimmed)
- GIVEN the LLM responds "finance.home" (no second line) and `now` is `2026-03-31T14:30:00Z`, WHEN classified, THEN `title` is exactly "Voice Memo 2026-03-31 14:30" (using format `"'Voice Memo' yyyy-MM-dd HH:mm"`, UTC)
- GIVEN the LLM responds with an empty string and `now` is `2026-03-31T14:30:00Z`, WHEN classified, THEN `folderPath` is nil and `title` is "Voice Memo 2026-03-31 14:30"
- GIVEN a classification call with hierarchy ["finance", "finance.home", "personal"], WHEN the system prompt sent to `MockLLMService` is examined, THEN it contains each hierarchy path as a substring ("finance", "finance.home", "personal") AND contains "GENERAL NOTES" as the fallback option AND contains instructions for the line-separated response format

**Do NOT:**
- Implement summarization logic — that is Task 4
- Handle the "should I summarize first?" decision — the caller provides the transcript (already summarized if needed)
- Create the note — this task only classifies; note creation is in Task 5
- Add prompt tuning or multiple prompt variations — use a single clear prompt; tuning comes from empirical testing later

---

### Task 4: Iterative Refine Summarizer

**Blocked By:** Task 0, Task 1

**Relevant Files:**
- `Libraries/Sources/Core/IterativeRefineSummarizer.swift` ← create
- `Libraries/Tests/CoreTests/IterativeRefineSummarizerTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/TranscriptSummarizer.swift` — the protocol this task implements: `summarize(transcript:contextBudget:)` with no `using:` parameter (Task 0)
- `Libraries/Sources/Core/LLMContextBudget.swift` — `LLMContextBudget` struct with `totalWords`, `systemPromptOverhead`, `summaryReserveRatio`, `availableForContent`, `availableForNewChunk` (Task 0)
- `Libraries/Sources/Core/LLMService.swift` — the LLM protocol injected at init time, used to send summarization prompts (Task 0)
- `Libraries/Tests/CoreTests/Mocks/MockLLMService.swift` — mock to control summarization responses and verify prompts sent (Task 1)

**Steps:**

1. [ ] Write failing tests for `IterativeRefineSummarizer.summarize(transcript:contextBudget:)`:
   - Test transcript that fits in one chunk (word count ≤ `availableForNewChunk`): LLM called once with summarize instruction, returns single summary
   - Test transcript requiring 2 chunks: LLM called twice — first with chunk 1, second with rolling summary + chunk 2; verify final result is second call's response
   - Test transcript requiring 3 chunks: LLM called 3 times with rolling summary accumulation
   - Test the invariant: for every LLM call, the user prompt's word count does not exceed `contextBudget.availableForContent` (check via `MockLLMService.calls`)
   - Test that chunk splitting respects word boundaries (does not split mid-word)
   - Test LLM error propagation: given a 3-chunk transcript, when the LLM throws on the second call, then the summarizer propagates the error (throws)
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `IterativeRefineSummarizer` struct conforming to `TranscriptSummarizer`, storing `llmService: any LLMService` at init. Implement word-count-based chunk splitting: split transcript into words, compute chunk size using `contextBudget.availableForNewChunk` (which accounts for the reserve ratio), group words into chunks of that size
4. [ ] Implement iterative refine loop: send first chunk to LLM with "summarize this transcript segment" instruction; for each subsequent chunk, send the previous summary + new chunk with "update this summary with the new content" instruction; return the final summary. Let LLM errors propagate — no catch or retry
5. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a transcript of 500 words and a context budget with `availableForNewChunk` of 1000, WHEN summarized, THEN the LLM is called exactly once (no chunking needed)
- GIVEN a transcript of 2000 words and a context budget with `availableForNewChunk` of 560 (800 * 0.7), WHEN summarized, THEN the LLM is called 4 times (2000/560 = 3.57, rounded up) and each call's user prompt word count is ≤ `availableForContent` (800)
- GIVEN a 3-chunk transcript, WHEN summarized, THEN each successive LLM call includes the rolling summary from the previous call
- GIVEN any summarization call, WHEN the user prompts sent to the LLM are examined, THEN no user prompt exceeds `contextBudget.availableForContent` words
- GIVEN a transcript with words, WHEN chunked, THEN chunks split at word boundaries (no partial words)
- GIVEN a 3-chunk transcript, WHEN the LLM throws an error on the second call, THEN the summarizer propagates the error without retrying

**Do NOT:**
- Classify the transcript — summarization produces a condensed text; classification is a separate step (Task 3)
- Decide whether summarization is needed — the caller (Task 5) makes that decision based on word count vs. context budget
- Use character-based splitting — use word-count-based splitting to match the context window's word-based limit
- Add sentence boundary detection — word boundaries are sufficient; sentence boundaries add complexity with minimal benefit

---

### Task 5: Note Routing Pipeline Stage

**Blocked By:** Task 1, Task 2, Task 3, Task 4

**Relevant Files:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` ← modify (implement the route method)
- `Libraries/Tests/CoreTests/NoteRoutingPipelineStageTests.swift` ← create

**Context to Read First:**
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` — the stage class with empty `route()` stub and `onComplete` callback parameter (Task 0)
- `Libraries/Sources/Core/TranscriptionPipelineStage.swift` — pattern for Stage 1: how it uses `store.markProcessed`, `logger`, and the `onResult` callback
- `Libraries/Sources/Core/FolderHierarchyBuilder.swift` — `buildFolderHierarchy(using:)` function (Task 2)
- `Libraries/Sources/Core/TranscriptClassifier.swift` — `classify(transcript:hierarchy:using:now:)` (Task 3)
- `Libraries/Sources/Core/MemoStore.swift` — `markProcessed(fileURL:date:)` for marking memo done
- `Libraries/Sources/Core/NotesService.swift` — `createNote(title:body:in:)` for note creation
- `Libraries/Sources/Core/NoteCreationResult.swift` — `.created` vs `.createdInDefaultFolder` results
- `Libraries/Tests/CoreTests/Mocks/MockLLMService.swift` — mock LLM for controlling classifier responses (Task 1)
- `Libraries/Tests/CoreTests/Mocks/MockTranscriptSummarizer.swift` — mock summarizer for controlling summary output (Task 1)
- `Libraries/Tests/CoreTests/Mocks/MockNotesService.swift` — mock Notes with per-parent support (Task 2)
- `Libraries/Tests/CoreTests/Mocks/MockMemoStore.swift` — mock store for verifying `markProcessed` calls

**Steps:**

Note: `TranscriptClassifier` is instantiated inline within `route()`, not injected as a dependency. Tests control classification behavior through `MockLLMService` responses. Use `MockTranscriptSummarizer` (not `IterativeRefineSummarizer`) to control summarization output independently of the LLM mock.

Note: `MockMemoStore` is an actor — access its properties with `await` (e.g., `let calls = await store.markProcessedCalls`). Other mocks use `nonisolated(unsafe)` and are accessed synchronously. The test struct should be `@MainActor` following the existing `TranscriptionPipelineStageTests` pattern.

1. [ ] Write failing tests covering all routing scenarios:
   - Short transcript: classifies, creates note in matched folder with full transcript body, marks processed, `onComplete` fires
   - Long transcript (exceeding context budget): `MockTranscriptSummarizer` returns a summary, classifier receives the summary, `createNote` receives the full original transcript as body
   - Empty transcript: skips classification and summarization, creates note in default folder with empty body, marks processed, `onComplete` fires
   - Unrecognized folder from classifier (LLM returns unknown path): creates note in default folder (nil), marks processed
   - Empty folder hierarchy (MockNotesService returns no folders): skips classification, creates note in default folder, marks processed
   - Model error/unavailable (MockLLMService throws): catches error, marks processed, logs error, `onComplete` fires, `route()` does not throw
   - Note creation error (MockNotesService.createNote throws): catches error, marks processed, logs error, `onComplete` fires, `route()` does not throw
   - Route-only mode with summarization: note body is full original transcript
   - Route-and-summarize mode with summarization: note body is the summary from `MockTranscriptSummarizer`
   - Route-and-summarize mode without summarization (short transcript): note body is the full transcript (summarizer not called)
   - Both modes produce identical classification prompts (compare `MockLLMService.calls` system prompts)
   - Folder match from classifier maps to correct `NotesFolder` for `createNote` (verify via `MockNotesService.createNoteCalls`)
   - Note creation returns `.createdInDefaultFolder`: logs the reason, still marks processed
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Implement `route()` entry point using a do/catch/cleanup pattern (not `defer`, since `defer` cannot contain `await`): extract transcript and fileURL from `TranscriptionResult`. Wrap the main logic in a `do` block. After the do/catch (in code that always executes regardless of path), call cleanup: `try? await store.markProcessed(fileURL:date:)` and `await onComplete()`. This guarantees cleanup runs on all paths — success, error, and early returns
4. [ ] Implement the main logic inside the `do` block: if transcript is empty, skip directly to note creation with default folder, empty body, and date-based title, then return (cleanup runs after)
5. [ ] Implement hierarchy discovery: call `buildFolderHierarchy(using: notesService)`. If hierarchy is empty, skip classification and create note in default folder with a date-based title, then return
6. [ ] Implement summarization decision: count words in transcript; if word count exceeds `contextBudget.availableForContent`, call `summarizer.summarize(transcript:contextBudget:)` to get condensed text for classification; otherwise use transcript directly
7. [ ] Implement classification: create a `TranscriptClassifier()` inline and call `classify(transcript:hierarchy:using:now:)` with the text (original or summarized) and `llmService`. Look up the returned `folderPath` in the hierarchy array to find the matching `NotesFolder` (or nil for default)
8. [ ] Implement note creation: determine the note body based on `routingMode` — `.routeOnly` uses full original transcript, `.routeAndSummarize` uses the summary (or full transcript if no summarization was needed). Call `notesService.createNote(title:body:in:)`. If result is `.createdInDefaultFolder`, log the reason
9. [ ] In the `catch` block: log the error. Cleanup (markProcessed + onComplete) executes after the catch block regardless — it is not inside the catch
10. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a short transcript "Buy groceries" and hierarchy containing "personal", WHEN `route()` is called with `MockLLMService` returning "personal\nGrocery list", THEN `MockNotesService.createNoteCalls` contains title "Grocery list", body "Buy groceries", in the "personal" `NotesFolder`, and `MockMemoStore.markProcessed` was called
- GIVEN a transcript exceeding the context budget and `MockTranscriptSummarizer` returning "condensed text", WHEN `route()` is called, THEN the `MockLLMService` classify call receives "condensed text" (not the full transcript), but `createNote` receives the full original transcript as body
- GIVEN an empty transcript "", WHEN `route()` is called, THEN `MockTranscriptSummarizer` is not called, `MockLLMService` is not called (classification skipped), `createNote` is called with an empty body in the default folder (nil), and `markProcessed` is called
- GIVEN `MockLLMService` throws an error, WHEN `route()` is called, THEN the error is logged via `MockWatcherLogger`, `markProcessed` is called, `onComplete` fires (verified via captured call count), and `route()` does not throw
- GIVEN `MockNotesService.createNote` throws an error, WHEN `route()` is called, THEN the error is logged, `markProcessed` is called, `onComplete` fires, and `route()` does not throw
- GIVEN `MockNotesService.listFoldersByParent` returns no folders for root, WHEN `route()` is called, THEN classification is skipped and the note is created in the default folder
- GIVEN `.routeOnly` mode and `MockTranscriptSummarizer` returning "summary", WHEN a note is created after summarization, THEN the note body is the full original transcript (not "summary")
- GIVEN `.routeAndSummarize` mode and `MockTranscriptSummarizer` returning "summary", WHEN a note is created after summarization, THEN the note body is "summary"
- GIVEN `.routeAndSummarize` mode and a short transcript that does not exceed the context budget, WHEN a note is created, THEN the note body is the full transcript (summarizer is not called)
- GIVEN either routing mode with the same transcript and hierarchy, WHEN classification occurs, THEN the `MockLLMService.calls` system prompts are identical
- GIVEN a `.createdInDefaultFolder(reason:)` result from `createNote`, WHEN the pipeline completes, THEN the reason is logged and the memo is still marked processed
- GIVEN any code path through `route()`, WHEN it completes (success or failure), THEN `markProcessed` is called exactly once and `onComplete` is called exactly once

**Do NOT:**
- Modify `PipelineController` — that is Task 6
- Add retry logic — spec says one attempt per memo
- Add UI notification of errors — just log them
- Make `route()` throw — it handles all errors internally (cleanup must always happen)

---

### Task 6: Pipeline Integration — Wire Stage 2 into PipelineController

**Blocked By:** Task 5

**Relevant Files:**
- `Libraries/Sources/Core/PipelineController.swift` ← modify
- `Libraries/Tests/CoreTests/PipelineControllerTests.swift` ← modify or create

**Context to Read First:**
- `Libraries/Sources/Core/PipelineController.swift` — current wiring: `onResult` logs "awaiting stage 2"; Stage 2 replaces this callback
- `Libraries/Sources/Core/PipelineScheduler.swift` — `releaseLock()` method that Stage 2 must call after routing completes
- `Libraries/Sources/Core/NoteRoutingPipelineStage.swift` — Stage 2 class with `route()` method (Task 5)
- `Libraries/Sources/Core/TranscriptionPipelineStage.swift` — Stage 1 pattern: how `onResult` callback is wired
- `Libraries/Tests/CoreTests/PipelineSchedulerTests.swift` — existing pipeline test patterns (if present)

**Steps:**

1. [ ] Write failing tests for `PipelineController` with Stage 2 wiring:
   - Test that when a routing stage factory is provided, the `onResult` callback delegates to `stage.route()` and the lock is released via `onComplete`
   - Test that when no routing stage factory is provided (nil), the `onResult` callback logs "awaiting stage 2" (backward compatibility)
   - Test end-to-end: a mock transcription service emits a result → Stage 2 receives it → note is created → `onComplete` releases the lock → memo is marked processed
2. [ ] Run tests to verify they fail (confirm RED state)
3. [ ] Add a routing stage factory parameter to `PipelineController.init`: `makeRoutingStage: (@Sendable @escaping (@Sendable () async -> Void) -> NoteRoutingPipelineStage)? = nil`. The factory receives the `onComplete` closure and returns a fully constructed stage. This avoids needing `PipelineController` to know the stage's other dependencies
4. [ ] In `start()`, if `makeRoutingStage` is set, construct the stage **once** (not per invocation) by calling the factory with the `onComplete` closure: `{ [scheduler] in await MainActor.run { scheduler.releaseLock() } }` — the `MainActor.run` is required because `PipelineScheduler.releaseLock()` is `@MainActor`-isolated while `onComplete` is `@Sendable`. Store the constructed stage in a local `let`. In the `onResult` closure, call `await stage.route(result)`. The lock is released by the stage's cleanup code calling `onComplete` — do NOT call `scheduler.releaseLock()` directly after `route()`. If no factory was provided, keep the current "awaiting stage 2" log message. Note: Stage 1's `Bool` return to the scheduler still drives the failure-path lock release (when `process()` returns `false`, the scheduler auto-releases). Stage 2 only runs on the success path (when `process()` returns `true` and the lock stays held)
5. [ ] Run tests to verify they pass (confirm GREEN state)

**Acceptance Criteria:**

- GIVEN a `PipelineController` initialized with a routing stage factory, WHEN Stage 1 emits a `TranscriptionResult`, THEN `route()` is called on the constructed Stage 2 with that result, and the pipeline lock is released via the `onComplete` callback
- GIVEN a `PipelineController` initialized without a routing stage factory (`nil`), WHEN Stage 1 emits a `TranscriptionResult`, THEN the "awaiting stage 2" message is logged and no routing occurs (backward compatibility)
- GIVEN a full pipeline run (Stage 1 → Stage 2), WHEN the routing stage completes (via its internal `defer` block calling `onComplete`), THEN the memo is marked processed and the scheduler lock is released exactly once

**Do NOT:**
- Modify `PipelineScheduler` — it already exposes `releaseLock()`
- Modify `TranscriptionPipelineStage` — it already emits results via `onResult`
- Add new parameters to `PipelineScheduler` — wire through `PipelineController` only
- Add UI wiring or app-level initialization — that is outside this plan's scope
