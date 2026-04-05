# Summarization Instructions

- **Date**: 2026-04-05
- **Status**: Approved
- **Author**: Dave / Claude
- **Project Spec**: [spec.md](../../../spec.md)

---

## What We Are Building

A way for the user to provide free-text instructions that guide how voice memo transcripts are summarized. The instructions appear as an input field in settings when summarization is enabled, accept up to 300 words, and are incorporated into the summarizer's prompt when present. When the field is empty or summarization is off, behavior is unchanged from today.

---

## Why This Exists

The summarizer uses a generic prompt that cannot be tailored. Different voice memos serve different purposes — meeting notes, personal reflections, task lists — and the user has no way to guide the LLM toward the style or focus that fits their needs. Without customization, the user must accept whatever summary the LLM produces or disable summarization entirely.

---

## Scope

### In

- User can write free-text instructions that guide summarization behavior
- Instructions are persisted and survive app restarts
- Instructions input is visible only when summarization is enabled; content is preserved when summarization is toggled off
- A 300-word limit is enforced in the UI (keystrokes ignored beyond the limit)
- The summarizer incorporates user instructions into its prompt when present
- The context budget accounts for instruction length dynamically to prevent context window overflow
- The settings window accommodates the new input area (current frame height will need to grow)

### Out

- Title generation is not affected — user instructions apply only to summarization
- No migration version bump needed — the new stored key is additive (defaults to `nil`)
- No validation beyond the 300-word UI limit (single-user app, user authors their own instructions)
- No prompt injection hardening for user-authored instructions (the user is the only author; transcript injection hardening in the prompt itself is unchanged)

---

## User Stories

### Story 1: Providing summarization instructions

As a user, I want to write instructions that guide how my voice memos are summarized, so that summaries match my preferred style and focus.

**Acceptance Criteria:**
1. When summarization is enabled, an instructions input area appears in the settings
2. The input accepts free-form text up to 300 words; when the field contains 300 words and the user types a character that would create word 301, the keystroke is ignored (word counting splits on all whitespace, matching the summarizer's existing word-splitting behavior)
3. Instructions persist across app restarts; a fresh install starts with no instructions (`nil`)
4. When summarization is enabled and instructions contain non-whitespace text, the system prompt sent to the LLM on every summarization chunk contains the base prompt followed by the user's instructions; when instructions are empty, the system prompt equals the base prompt exactly with no trailing whitespace or separators
5. When instructions are present, the context budget's system prompt overhead increases by the word count of the instructions, so that chunk sizing accounts for the longer prompt

### Story 2: Summarization without instructions

As a user, I want summarization to work exactly as before when I leave the instructions field empty, so that existing behavior is not disrupted.

**Acceptance Criteria:**
1. When the instructions field is empty, the summarizer prompt is identical to today's prompt — no extra whitespace, no separators, no "instructions:" prefix
2. When summarization is toggled off, the instructions input is hidden; when toggled back on, the previously entered instructions are displayed unchanged

---

## Edge Cases

1. **Whitespace-only instructions** — treated as empty; the system prompt is identical to the base prompt with no modification
2. **Instructions at exactly 300 words** — accepted; the UI prevents word 301
3. **Instructions change mid-processing** — the config is read per-memo, so the next memo picks up the new instructions; the currently-processing memo uses the instructions that were active when its pipeline run started (guaranteed by the existing config snapshot pattern)
4. **Very short instructions (1-2 words)** — valid; appended to system prompt as-is; no minimum length enforced (this is intentional)
5. **Budget impact of long instructions** — 300 words of instructions increases the effective system prompt overhead, reducing the chunk size for iterative refinement; the budget must account for this dynamically to avoid exceeding the context window or triggering the budget's fatal precondition (`totalWords > systemPromptOverhead`)

---

## Success Criteria

1. A user can type summarization instructions, and the LLM's system prompt for summarization includes those instructions on every chunk
2. Leaving instructions empty produces identical prompt behavior to today
3. The 300-word limit is enforced in the UI — the user cannot type beyond it
4. Instructions survive app restarts

---

## Technical Context

- **Settings storage**: `UserSettings` uses `@Observable` with manual `access`/`withMutation` calls around `UserDefaults` reads/writes. New `summarizationInstructions: String?` property follows this pattern
- **Config flow**: `UserSettings` → `RoutingConfiguration` (value type snapshot, new `summarizationInstructions` field) → `NoteRoutingPipelineStage.configProvider` closure (read per-memo). `readRoutingConfiguration(from:)` is `nonisolated static` and must also thread the new field
- **Summarizer design**: Instructions flow per-call through the protocol (new `instructions` parameter on `TranscriptSummarizer.summarize`), not at init time. This matches the `configProvider` pattern — settings changes take effect on the next memo without reconstructing the summarizer. The `NoteRoutingPipelineStage` reads instructions from the config snapshot and passes them to the summarizer call
- **Budget**: `LLMContextBudget.systemPromptOverhead` (currently fixed at 200 words in `AppDelegate`) must account for instruction length. The `IterativeRefineSummarizer` owns both prompt construction and budget adjustment — when instructions are present, it computes `adjustedOverhead = baseOverhead + instructionWordCount` internally and creates a new budget before chunking. This keeps budget math co-located with prompt construction
- **Word counting**: Both the UI limit and the budget calculation must use `split(whereSeparator: \.isWhitespace)` to match the summarizer's existing word-splitting behavior
- **UI**: `SettingsView` uses SwiftUI `Form` with `.grouped` style; frame is currently hardcoded at `480 x 300` and will need to grow to accommodate the instructions input
- **Historical note**: A previous `customPrompt` / `useCustomPrompt` feature was removed in migration v1; this is a cleaner re-introduction scoped only to summarization

---

## Dependencies

- No new external dependencies
- Builds on existing `RoutingConfiguration` data flow and `TranscriptSummarizer` protocol

---

## Open Questions

None — all decisions resolved during planning.
