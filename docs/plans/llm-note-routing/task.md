# LLM Note Routing — Task Breakdown (Complete)

**Plan**: [plan.md](plan.md)
**Completed**: 2026-03-31
**Status**: Complete

## Summary

- Implemented Pipeline Stage 2: LLM-based transcript classification into Apple Notes folders with title generation, iterative summarization for long transcripts, and two routing modes (route-only, route-and-summarize)
- Added 7 new source files in Libraries/Sources/Core/ (protocols, types, and implementations) plus 1 concrete Foundation Model adapter in Utterd/Core/
- 9 commits, +1,695 lines across 22 files, 125 tests passing (42 new tests added)
- Automated code review (2 iterations) resolved all findings: preconditions, cycle detection, parsing hardening, title sanitization, documentation updates

## Leftover Issues

- N+1 AppleScript calls in FolderHierarchyBuilder (acceptable for typical folder counts of 10-20; optimize with bulk fetch if performance becomes an issue)
- FoundationModelLLMService creates a new LanguageModelSession per call (intentional for different system prompts; revisit if session setup cost is significant)
