# Immediate Queue-Based Pipeline — Task Breakdown (Complete)

**Plan**: [plan.md](plan.md)
**Completed**: 2026-04-05
**Status**: Complete

## Summary

- Replaced 30-second polling scheduler with immediate AsyncStream-based queue processing — memos begin processing as soon as they're detected
- Added permanent failure recording (dead queue) with reason and timestamp via `markFailed` on MemoStore — failed items are never retried and are excluded from future processing
- Added file-based logging (`FileWatcherLogger` + `CompositeWatcherLogger`) writing to `~/Library/Application Support/Utterd/utterd.log` with 10MB rotation
- Refactored pipeline stages to return failure info to caller instead of silently marking failed records as processed; 8 commits, +1797/-802 lines, 134 tests passing

## Leftover Issues

- `oldestUnprocessed()` is no longer called in production code (only in tests) — consider removing from protocol in a follow-up
- Historical plan docs (`docs/plans/user-settings/`) reference removed `onComplete` callback and "30s polling" — stale but low-impact
