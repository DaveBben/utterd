# LLM Note Routing Plan

**Date**: 2026-03-31
**Status**: Approved
**Author**: Claude
**Project Spec**: spec.md

---

## Why This Exists

The user records voice memos to capture thoughts and information that belong in specific Apple Notes folders. Today, the app transcribes these memos but does nothing with the transcript — each one requires the user to manually read it, decide which folder it belongs in, and create the note themselves. This manual triage defeats the purpose of hands-free voice capture and causes memos to pile up unprocessed.

---

## What We Are Building

Pipeline Stage 2: after a voice memo is transcribed, the app will use the on-device language model to read the transcript and decide which Apple Notes folder it belongs in. Long transcripts that exceed the model's context window are condensed via iterative summarization before classification. The full original transcript is then saved as a note in the chosen folder. The system is structured so a future "summarize" mode can replace the note body with a summary instead of the full transcript.

---

## Scope

### In
- Iterative "refine" summarization for transcripts exceeding the model's context window (~3K words)
- Recursive folder hierarchy discovery (walking `listFolders` at each level to build the full tree)
- LLM classification of transcript to a Notes folder (and title generation) using the user's actual folder hierarchy
- Note creation in the classified folder with the full original transcript as the body
- A routing mode parameter that accepts "route only" and "route and summarize" values (only "route only" is active)
- Wiring Stage 2 into the existing pipeline so transcription results flow into classification automatically
- Pipeline lock release and memo record marking after every code path (success or failure)
- Integration tests for the summarization, classification, and end-to-end routing logic

### Out (explicitly)
- Reminders / Calendar routing — separate future stage; this is Notes-only
- Remote LLM provider (OpenAI-compatible HTTP fallback) — deferred to a later task
- UI toggle for "route only" vs "route + summarize" — future UI work; code supports both modes but only "route only" is active
- Rich text or HTML note formatting — Notes integration uses plain text only
- Automatic retry on LLM failure — spec says each memo attempted once, no automatic retry

---

## Technical Context

- **Platform**: macOS 26+, Swift 6.2 (strict concurrency: complete)
- **On-device LLM**: macOS Foundation Model framework (macOS 26+ only)
- **Notes integration**: Existing `NotesService` protocol with `listFolders(in:)`, `resolveHierarchy(for:)`, and `createNote(title:body:in:)` via AppleScript
- **Pipeline handoff**: `TranscriptionPipelineStage` emits `TranscriptionResult(transcript: String, fileURL: URL)` via async callback; pipeline lock stays held until Stage 2 releases it
- **Existing patterns**: Protocol-based service abstractions in `Libraries/Sources/Core/`, concrete implementations in `Utterd/Core/`, mocks in test targets
- **Context window**: ~3K words (~4K tokens); chunk sizing must leave room for system prompt and rolling summary

---

## User Stories

### US-01 — Memo routing to Notes folder
As a user,
I want my voice memos to be automatically filed into the correct Notes folder,
So that I don't have to manually sort transcripts.

**Acceptance Criteria**
- [ ] AC-01.1: GIVEN a transcript shorter than the context window and a folder hierarchy with multiple folders, WHEN the pipeline processes the memo, THEN a note is created in the folder the model selects with the title the model generates
- [ ] AC-01.2: GIVEN a transcript and a folder hierarchy, WHEN the model responds with "GENERAL NOTES" or a string that doesn't match any known folder path, THEN the note is created via the default folder (no folder specified), and the pipeline completes successfully
- [ ] AC-01.3: GIVEN a successful note creation, WHEN the pipeline completes, THEN the memo record is marked as processed and the pipeline lock is released
- [ ] AC-01.4: GIVEN an empty transcript (empty string from Stage 1), WHEN the pipeline processes the memo, THEN classification is skipped, a note is created in the default folder with an empty body, the memo is marked processed, and the lock is released
- [ ] AC-01.5: GIVEN the model selects a folder but note creation fails with an error, WHEN the pipeline handles the error, THEN the memo is marked as processed, the pipeline lock is released, and the error is logged
- [ ] AC-01.6: GIVEN a folder hierarchy containing "finance.home", WHEN the model responds with " Finance.Home " (extra whitespace, different casing), THEN the note is created in the "finance.home" folder, not the default folder
- [ ] AC-01.7: GIVEN a transcript and an empty folder hierarchy (Notes service returns zero folders), WHEN the pipeline processes the memo, THEN classification is skipped, a note is created in the default folder, the memo is marked processed, and the lock is released
- [ ] AC-01.8: GIVEN a model response that includes a folder but no parseable title, WHEN the pipeline creates the note, THEN a date-based fallback title is used and the note is still created successfully

### US-02 — Long memo routing
As a user,
I want long voice memos (exceeding the model's context window) to be routed to the correct folder,
So that even lengthy recordings are automatically organized.

**Acceptance Criteria**
- [ ] AC-02.1: GIVEN a transcript exceeding the context window limit, WHEN the pipeline processes the memo, THEN the text sent to the model for classification is shorter than the original transcript AND the note is still created in an appropriate folder
- [ ] AC-02.2: GIVEN a long transcript that was summarized for classification, WHEN the note is created, THEN the note body contains the full original transcript, not the summary
- [ ] AC-02.3: GIVEN a transcript that requires multiple summarization chunks, WHEN summarization completes, THEN no single prompt sent to the model exceeds the context window limit

### US-03 — Future summarize mode readiness
As a developer,
I want the routing pipeline to accept a mode parameter controlling whether the note body is the full transcript or a summary,
So that a future UI toggle can activate summarization without changing the pipeline internals.

**Acceptance Criteria**
- [ ] AC-03.1: GIVEN the pipeline is configured for "route only" mode, WHEN a memo is processed, THEN the note body is the full original transcript
- [ ] AC-03.2: GIVEN the pipeline is configured for "route and summarize" mode, WHEN a memo is processed, THEN the note body is the condensed summary
- [ ] AC-03.3: GIVEN either mode, WHEN the pipeline classifies a transcript, THEN the classification prompt sent to the model is identical in both modes — mode only affects the note body content

Note: AC-03.1 and AC-03.3 represent the active behavior. AC-03.2 is testable via mocks but the mode is not exposed in the UI.

### US-04 — Pipeline integration
As a user,
I want transcription results to automatically flow into classification and routing,
So that the entire pipeline runs end-to-end without manual intervention.

**Acceptance Criteria**
- [ ] AC-04.1: GIVEN a transcription completes successfully, WHEN the transcription stage emits a result, THEN a note is created in the appropriate folder using the transcript from Stage 1 — verifying end-to-end flow from transcription through classification to note creation
- [ ] AC-04.2: GIVEN the routing stage completes (success or failure), THEN the memo is marked as processed and the pipeline lock is released
- [ ] AC-04.3: GIVEN the model is unavailable or returns an error, WHEN the routing stage handles the failure, THEN the memo is marked as processed, the lock is released, and the error is logged — no retry is attempted

---

## Domain: Folder Hierarchy Formatting

The system prompt presents the user's Notes folder hierarchy to the model. The hierarchy is discovered at runtime via the Notes service. Folders are presented as a flat list using dot notation for nesting (chosen because the user's description used this format):

```
finance
finance.home
finance.taxes
personal
personal.health
work
work.projects
work.projects.utterd
```

The model replies with a folder path (e.g., `finance.home`) or `GENERAL NOTES` if no folder fits, **and** a short title for the note. The response contains both fields — the exact response format (e.g., line-separated, JSON, or delimited) is an implementation detail resolved during task refinement.

---

## Domain: Refine Summarization Strategy

For transcripts exceeding the context window, the system uses an iterative "refine" approach:

1. Compute available space per chunk: context window limit minus the size of the system prompt (including folder list) minus the rolling summary overhead
2. Split transcript into chunks that fit within the available space
3. Send the first chunk to the model with an instruction to summarize
4. For each subsequent chunk, send the previous rolling summary + the new chunk, asking the model to produce an updated summary
5. After all chunks are processed, the final rolling summary is used for folder classification

This ensures the model never receives more text than it can handle, while preserving the overall meaning of the full transcript.

---

## Edge Cases

- **Empty transcript**: Stage 1 can emit an empty string. Skip classification, create note in default folder with empty body, mark processed, release lock.
- **Model returns unrecognized folder name**: If the model's response doesn't match any known folder path (typo, hallucination), treat as "GENERAL NOTES" and route to the default folder.
- **Model returns response with extra whitespace or casing differences**: Folder matching should be case-insensitive and trim whitespace before comparison.
- **Folder hierarchy is empty**: If the Notes service returns no folders (new user, empty Notes), skip classification and route to the default folder.
- **Folder deleted between classification and creation**: `createNote` already handles this — returns a fallback result. The pipeline should log the fallback but still succeed.
- **Model unavailable or errors**: Mark the memo as processed (prevent infinite reprocessing), log the error, and release the pipeline lock. No retry.
- **Note creation throws an error**: Mark processed, release lock, log the error. The memo is not retried.
- **Transcript near context window boundary**: Use a conservative threshold to decide whether summarization is needed, leaving margin for the system prompt and folder list. The threshold is a named constant, not a magic number.
- **Very short transcript (a few words)**: Goes through classification normally — the model can handle short inputs.
- **Deeply nested folder hierarchy**: Dot notation works at any depth. The folder list may consume significant context window space — chunk size calculation receives the system prompt size (including folder list) as input, not a hardcoded constant.
- **Folder name contains a dot**: Dot notation could be ambiguous. Folder matching uses the known hierarchy to resolve — match against the actual folder paths discovered from the Notes service, not by splitting on dots.
- **Model returns empty or missing title**: If the model's response doesn't include a parseable title, fall back to a date-based title (e.g., "Voice Memo 2026-03-31 14:30") rather than failing. The note should still be created.
- **Model response is unparseable**: If the response cannot be parsed into folder + title at all (garbled output), treat as "GENERAL NOTES" with a date-based fallback title.

---

## Success Criteria

1. 100% of processed memos result in either a note created in the correct folder or a note in the default folder with a logged reason — zero memos silently dropped
2. Zero orphaned pipeline locks — every code path (success, model error, note creation error) releases the lock and marks the memo as processed
3. Transcripts exceeding 3K words are successfully condensed and classified without model context overflow errors
4. Integration test suite covering at least 8 named scenarios passes with zero failures: short transcript routing, long transcript summarization + routing, unrecognized folder fallback, empty transcript, model failure, note creation failure, case-insensitive folder matching, and empty folder hierarchy

---

## Dependencies & Assumptions

**Dependencies**
- macOS Foundation Model framework available and functional for unsandboxed apps (macOS 26+)
- Existing `NotesService` protocol and `AppleScriptNotesService` implementation
- Existing `PipelineController` and `PipelineScheduler` for lock management
- Stage 1 (`TranscriptionPipelineStage`) delivering `TranscriptionResult`

**Assumptions**
- The Foundation Model context window is approximately 3K words (~4K tokens); chunk sizing is based on this estimate and uses a named constant that can be adjusted
- The Foundation Model can follow the system prompt format reliably enough to return a folder name (or "GENERAL NOTES") and a note title without structured output / function-calling support
- The folder hierarchy is relatively stable during a single memo's processing (folders won't be created/deleted mid-classification)
- The summarization threshold is set conservatively (system prompt + folder list + margin subtracted from context window) — this is an engineering estimate that may need tuning after empirical testing with the Foundation Model
- Dot notation is used for folder hierarchy presentation because the user specified this format; if model response quality is poor, the format can be changed without affecting the plan's behavioral requirements

---

## Open Questions

**All open questions must be resolved before task refinement begins.**

- [x] Should the note title be auto-generated (e.g., first N words of the transcript, or a date-based title), or should the model also be asked to generate a title?
  - Context: `createNote` requires a `title` parameter. This affects whether classification needs one LLM call or two, and changes the prompt design and mock surface for testing.
  - Options considered: (a) Date-based title like "Voice Memo 2026-03-31 14:30" — simplest, no extra LLM call, (b) First ~10 words of transcript — simple, provides context, (c) Ask the model to generate a title alongside classification — richer but adds complexity
  - Decision needed by: Before task refinement
  - Decision: Option (c) — ask the model to generate a title alongside classification
  - Reasoning: The model already has the transcript context and folder hierarchy; asking it to also produce a title in the same call gives the user a meaningful note title without an extra LLM round-trip

- [x] Does `listFolders(in: nil)` return only top-level folders, or all folders recursively? The protocol documentation says "immediate child folders" suggesting top-level only — if so, the pipeline needs recursive calls to build the full hierarchy.
  - Context: The system prompt requires the complete folder hierarchy in dot notation. If `listFolders` only returns one level, we need recursive traversal logic (and tests for it). The existing notes-service task flagged this same question for empirical validation.
  - Options considered: (a) `listFolders` returns only immediate children — need recursive traversal, (b) A bulk-fetch approach using existing service methods
  - Decision needed by: Before task refinement
  - Decision: Option (a) — `listFolders` returns immediate children only; recursive traversal is needed
  - Reasoning: Confirmed by user — the protocol docs are accurate, it returns one level at a time

---

## Out of Scope (Clarification)

- **Tri-way classification (Reminders / Calendar / Notes)** — discussed because the spec describes it as the full Stage 2 vision. Deferred: this task handles Notes-only routing as the first concrete slice. Reminders and Calendar routing will be separate tasks that extend the classification prompt.
- **Remote LLM fallback** — discussed because the spec plans for it. Deferred: the protocol abstraction will make adding a remote provider straightforward, but this task only implements the Foundation Model provider.
- **Note formatting (rich text, headers, bullet points)** — discussed because summarized notes might benefit from structure. Deferred: Notes integration currently supports plain text only.
