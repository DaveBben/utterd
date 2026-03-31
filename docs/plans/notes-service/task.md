# Notes Service Interface — Task Breakdown (Complete)

**Plan**: [docs/plans/notes-service/plan.md](plan.md)
**Completed**: 2026-03-31
**Status**: Complete

## Summary

- Defined `NotesService` protocol, `NotesFolder`, `NoteCreationResult`, and `NotesServiceError` in `Libraries/Sources/Core/`
- Implemented `AppleScriptNotesService` with `ScriptExecutor` testability seam, string escaping, folder listing, hierarchy resolution, note creation with fallback, and existence verification
- Added 27 unit tests (via `MockScriptExecutor`) and 9 integration tests (via `NSAppleScriptExecutor` with graceful skip when Notes is inaccessible)
- Updated entitlements, Info.plist, project.yml, spec.md, and README for Apple Events automation

**Commits**: 10 (8 tasks + 2 review fix rounds)
**Lines**: +1,071 across 17 files (excluding docs)

## Leftover Issues

- `listFolders(in: nil)` behavior depends on Apple Notes' `folders of default account` semantics — validate empirically whether it returns only top-level or all folders
- `noteExists` uses AppleScript `contains` which may do substring matching in single-note folders — use `(name of notes as list) contains` if this causes issues
- Performance: AppleScript string concatenation is O(n²) and `createNote` with a folder does two IPC round-trips — acceptable for current use but could be optimized if needed
