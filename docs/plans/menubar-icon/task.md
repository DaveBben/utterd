# Menu Bar Icon — Task Breakdown (Complete)

**Plan**: [plan.md](plan.md)
**Completed**: 2026-03-30
**Status**: Complete

## Summary

- Converted Utterd from a windowed app to a menu-bar-only daemon with `LSUIElement: true`
- Added `MenuBarExtra` with native `.menu` style dropdown showing sync status, Settings (no-op), and Quit
- Gated menu bar icon visibility behind `permissionResolved` flag to prevent ghost icon before FDA check
- 8 commits, +130 lines across 10 files, 19 tests passing (7 new)

## Leftover Issues

- **Cmd+, regression**: `LSUIElement` removes the app menu bar, breaking the Cmd+, shortcut for Settings. Deferred to a future plan that wires the "Settings..." menu item.
- **Static placeholders**: Sync info shows hardcoded strings; real watcher integration is a separate plan.
