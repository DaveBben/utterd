# Menu Bar Icon Plan

**Date**: 2026-03-30
**Status**: Approved
**Author**: Claude + Dave
**Project Spec**: spec.md

---

## What We Are Building

When Utterd launches, it will appear as a waveform icon in the macOS menu bar instead of opening a window. Clicking the icon reveals a popover showing the last synced voice memo name and timestamp, along with a Settings item and a Quit button. For this initial version, the sync information is a static placeholder — real data integration comes later.

---

## Why This Exists

Users have no persistent, low-interruption indicator that the voice memo triage pipeline is running. Without an ambient signal, the only way to verify the daemon is active is to open Activity Monitor or look for a window — both of which defeat the "silent and automatic" promise of the tool. Users also need a low-friction way to inspect last activity and stop the daemon without resorting to system tools.

---

## Scope

### In
- Menu bar icon using a waveform visual, visible on app startup
- Popover showing last synced voice memo name and datetime (see layout table below)
- Static placeholder strings for the sync info (no real watcher integration)
- "Settings..." menu item (non-functional for now)
- "Quit Utterd" menu item that terminates the app immediately (no confirmation dialog)
- App runs without any main window (menu-bar-only)
- App does not appear in the Dock while running
- Existing Settings scene (Cmd+,) continues to function (regression preservation)

### Out (explicitly)
- Real voice memo watcher integration for sync status — deferred to a future plan
- Wiring the popover "Settings..." button to open the Settings window — deferred (the button is a visible placeholder; Cmd+, still works)
- Any notification or alert system
- Custom icon artwork — using built-in system symbol
- Popover auto-dismiss behavior customization

---

## User Stories

### US-01 — See the daemon is running
As the user,
I want to see Utterd's icon in my menu bar when the app is running,
So that I know the daemon is active without needing a dock icon or open window.

**Acceptance Criteria**
- [ ] AC-01.1: GIVEN the app is not running, WHEN the user launches Utterd, THEN a waveform icon appears in the macOS menu bar and no window opens
- [ ] AC-01.2: GIVEN the app is running, WHEN the user looks at the Dock, THEN Utterd does not appear as a Dock icon
- [ ] AC-01.3: GIVEN the app does not have Full Disk Access, WHEN the user launches Utterd, THEN the permission alert appears before any menu bar icon is shown
- [ ] AC-01.4: GIVEN the permission alert is showing, WHEN the user clicks "Quit" on the alert, THEN the app terminates and no menu bar icon remains
- [ ] AC-01.5: GIVEN the app is running, WHEN the user activates the app via Cmd-Tab or double-clicks the app in Finder, THEN no window opens

### US-02 — Check last sync status
As the user,
I want to click the menu bar icon and see the last synced voice memo info,
So that I can quickly verify the daemon is processing memos.

**Acceptance Criteria**
- [ ] AC-02.1: GIVEN the app is running, WHEN the user clicks the menu bar icon, THEN a popover appears showing the text "Last Voice Memo Synced" as the title and "Yesterday, 1:25 AM" as the subtitle
- [ ] AC-02.2: GIVEN the popover is open, WHEN the user clicks the menu bar icon again, THEN the popover dismisses
- [ ] AC-02.3: GIVEN the popover is open, WHEN the user clicks outside the popover, THEN the popover dismisses
- [ ] AC-02.4 (manual visual check): GIVEN the popover is open, WHEN the user inspects the layout, THEN the title appears as a primary line, the subtitle as a secondary line below it, and a divider separates them from the action items (see layout table)

### US-03 — Quit the app
As the user,
I want to quit Utterd from the menu bar popover,
So that I can stop the daemon without needing Activity Monitor or a terminal.

**Acceptance Criteria**
- [ ] AC-03.1: GIVEN the popover is open, WHEN the user clicks "Quit Utterd", THEN the application terminates immediately with no confirmation dialog

### US-04 — Access settings (placeholder)
As the user,
I want to see a Settings option in the popover,
So that the UI is ready for future configuration even though it does nothing yet.

**Acceptance Criteria**
- [ ] AC-04.1: GIVEN the popover is open, WHEN the user views the action items, THEN a clickable "Settings..." item appears between the divider and the "Quit Utterd" item
- [ ] AC-04.2: GIVEN the popover is open, WHEN the user clicks "Settings...", THEN the click is accepted with no visible effect (no window opens, no alert appears, no error is logged)
- [ ] AC-04.3 (regression check): GIVEN the app is running as a menu-bar-only app, WHEN the user presses Cmd+, THEN the existing Settings window opens and functions correctly — this is not new functionality but must survive the migration

---

## Menu Bar Popover Layout

The popover content, from top to bottom:

| Element | Content | Behavior |
|---------|---------|----------|
| Title line | `Last Voice Memo Synced` (static) | Non-interactive label |
| Subtitle line | `Yesterday, 1:25 AM` (static placeholder) | Non-interactive label |
| Divider | Horizontal separator | Visual only |
| Settings | `Settings...` | Clickable, no-op for now |
| Quit | `Quit Utterd` | Terminates the app |

---

## Edge Cases

- **App launched without Full Disk Access**: The existing permission gate in AppDelegate fires before the menu bar appears. The alert flow must complete (user quits or opens System Settings) before the menu bar icon becomes visible, to prevent ghost icons.
- **MenuBarExtra initialization order vs permission alert**: The permission alert in AppDelegate must fire and resolve before the menu bar scene becomes visible. If the scene lifecycle differs from the previous windowed setup, the menu bar icon could appear before the alert. This must be verified during implementation and may require deferring menu bar creation until after the permission check passes.
- **Multiple launches**: macOS prevents duplicate menu bar items for the same app since only one instance runs. No special handling needed.
- **Popover already open when icon clicked again**: macOS handles toggle behavior natively — clicking the icon while the popover is open dismisses it.
- **System appearance change (light/dark mode)**: System symbols adapt automatically to system appearance. No custom handling needed.
- **Menu bar overflow (too many icons)**: macOS handles menu bar overflow natively. Utterd's icon follows standard system behavior.

---

## Success Criteria

1. App launches with zero windows — only a menu bar icon is visible
2. Zero crash reports or unresponsive conditions observed during manual popover interaction (open, read status, quit, dismiss)
3. Zero Dock icon appearances while the app is running

---

## Dependencies & Assumptions

**Dependencies**
- macOS 15.0+ deployment target
- Project spec: spec.md

**Assumptions**
- The existing AppDelegate permission gate (Full Disk Access check) will continue to work when the main window is removed — the alert is presented via NSAlert, not a scene-level view, so it is independent of the scene type. If this proves false, the permission check may need to move or the menu bar creation may need to be deferred.
- A macOS 15+ menu-bar-only app can display a popover with title text, secondary text, a divider, and two action items using only platform-standard UI primitives
- Removing the main window will not break the existing Settings scene — macOS supports menu-bar-only apps with a separate Settings scene. This is a key assumption that must be verified early in implementation.

---

## Open Questions

- [x] Should the popover use real sync data or static placeholders?
  - Context: The watcher pipeline exists but routing to AppState is not yet built
  - Options considered: Static placeholders now, real data now, or a hybrid with "no data yet" state
  - Decision: Static placeholders — decouple UI work from pipeline integration
  - Reasoning: Allows the menu bar UI to be built and tested independently; real data integration is a separate plan

- [x] Should clicking "Settings..." in the popover open the Settings window?
  - Context: A Settings scene already exists in the app, accessible via Cmd+,
  - Options considered: Wire it now, leave as no-op, show "coming soon" tooltip
  - Decision: Leave as no-op; Cmd+, still opens Settings via the existing scene
  - Reasoning: Wiring the button is trivial future work; the placeholder communicates intent without adding scope

- [x] Should Quit show a confirmation dialog?
  - Context: Some apps confirm before quitting to prevent accidental termination
  - Options considered: No confirmation, "Are you sure?" dialog
  - Decision: No confirmation dialog
  - Reasoning: User explicitly requested immediate quit; this is a background daemon, not a document editor with unsaved work

---

## Out of Scope (Clarification)

- **Real sync status from VoiceMemoWatcher** — discussed because the popover shows sync info, but wiring the watcher to AppState is a separate feature. Static placeholders used here so the UI can be built and tested independently.
- **Settings window functionality via popover button** — the Settings scene already exists in the codebase and remains accessible via Cmd+,. Wiring the popover "Settings..." button to open it will be a separate small change once the menu bar is in place.
- **Notification badges or icon state changes** — came up implicitly (daemon status), but visual state changes to the icon (e.g., red dot for errors) are deferred until the processing pipeline exists.
