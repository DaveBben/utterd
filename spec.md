# Utterd Spec
**Branch**: `main`
**Date**: 2026-03-23
**Status**: Draft
**Author**: Dave

---

## Why This Exists

Capturing ideas, tasks, and events in the moment is high friction. Even something as simple as opening Notes and finding the right folder takes long enough to break focus and lose the thought. People already speak into Voice Memos as a reflex, but those recordings sit untriaged — a growing backlog of intentions that never reach the systems where they would actually be useful.

---

## Scope

### In
- Monitor for new Apple Voice Memos arriving on macOS
- Extract the transcript that Apple embeds in voice memo audio files
- Classify each transcript's intent (task, calendar event, or reference material) using a local LLM
- Route tasks to Apple Reminders as new reminders
- Route calendar events to Apple Calendar as new events (default 30-minute duration when unspecified)
- Route reference material to Apple Notes with an LLM-generated title and summary (not raw transcript)
- Deduplicate by filename — the same file is never processed twice, but identical content in different files is processed independently
- Skip voice memos that contain no embedded transcript (silent, no processing or alert)
- Queue unprocessed memos and retry automatically when the local LLM becomes available
- Surface memos that fail due to Apple API errors in an Alerts view with the reason for failure (read-only, no retry)
- Surface memos with ambiguous date/time information for calendar events in the Alerts view
- Menu bar icon with three options: Settings, Alerts, Quit
- Settings interface for customizing the LLM classification prompt, including target lists, folders, and calendars
- Default destinations (default Reminders list, default Calendar, default Notes folder) so it works with zero configuration
- Entire pipeline runs locally — no cloud services, no network dependency

### Out (explicitly)
- Local speech-to-text or transcription fallback — the app relies entirely on Apple's embedded transcript
- Manual retry or user-initiated actions on failed alerts — alerts are informational only
- Preserving the original raw transcript in created Reminders, Calendar events, or Notes
- Full windowed application — the only UI surfaces are the menu bar popover, Settings, and Alerts
- Multi-user support, authentication, or role-based access
- Monetization or licensing infrastructure

---

## User Stories

### US-01 — Automatic triage of a voice memo into a task
As a user,
I want a voice memo like "remind me to buy groceries tomorrow" to automatically appear as a reminder in Apple Reminders,
so that I never have to manually transfer spoken tasks into my task manager.

**Acceptance Criteria**
- [ ] AC-01.1: A new voice memo with a task-intent transcript is created as a reminder in the configured Reminders list
- [ ] AC-01.2: The reminder title reflects the content of the transcript
- [ ] AC-01.3: The voice memo filename is recorded so the same file is not processed again
- [ ] AC-01.4: If no Reminders list is configured, the reminder is created in the system default list

---

### US-02 — Automatic triage of a voice memo into a calendar event
As a user,
I want a voice memo like "meeting with Sarah on Friday at 2pm" to automatically appear as a calendar event,
so that my schedule stays current without manual data entry.

**Acceptance Criteria**
- [ ] AC-02.1: A new voice memo with a calendar-event-intent transcript is created as an event in the configured calendar
- [ ] AC-02.2: The event title, date, and time reflect the content of the transcript
- [ ] AC-02.3: When no duration is specified in the transcript, the event defaults to 30 minutes
- [ ] AC-02.4: If no calendar is configured, the event is created in the system default calendar
- [ ] AC-02.5: If the transcript contains ambiguous or unparseable date/time information, the memo appears in the Alerts view with a description of the problem

---

### US-03 — Automatic triage of a voice memo into a note
As a user,
I want a voice memo containing a general thought or reference material to appear in Apple Notes with a clear title and summary,
so that my ideas are organized and findable without manual cleanup.

**Acceptance Criteria**
- [ ] AC-03.1: A new voice memo with a reference-material-intent transcript is created as a note in the configured Notes folder
- [ ] AC-03.2: The note has an LLM-generated title (not the raw transcript or filename)
- [ ] AC-03.3: The note body contains an LLM-generated summary (not the raw transcript)
- [ ] AC-03.4: If no Notes folder is configured, the note is created in the default folder

---

### US-04 — Memos without transcripts are ignored
As a user,
I want voice memos that have no embedded transcript to be silently skipped,
so that the system does not create empty or meaningless items in my apps.

**Acceptance Criteria**
- [ ] AC-04.1: A voice memo with no embedded transcript produces no reminder, event, or note
- [ ] AC-04.2: A voice memo with no embedded transcript does not appear in the Alerts view
- [ ] AC-04.3: The filename is recorded per US-09 deduplication rules so it is not re-examined on future runs

---

### US-05 — Resilience when the local LLM is unavailable
As a user,
I want memos to be queued and retried automatically when the local LLM is down,
so that no voice memo is lost just because of a temporary service outage.

**Acceptance Criteria**
- [ ] AC-05.1: When the LLM is unreachable, new memos are added to a processing queue
- [ ] AC-05.2: Queued memos are retried automatically when the LLM becomes available
- [ ] AC-05.3: No memo is dropped or marked as failed due to LLM unavailability alone

---

### US-06 — Alerts for processing failures
As a user,
I want to see which memos failed to process and why,
so that I am aware of problems even though the system runs in the background.

**Acceptance Criteria**
- [ ] AC-06.1: When creating a reminder, event, or note fails due to an Apple API error, the memo appears in the Alerts view
- [ ] AC-06.2: Each alert displays the memo filename and a human-readable reason for the failure
- [ ] AC-06.3: The Alerts view is read-only — there are no retry or dismiss actions
- [ ] AC-06.4: When the LLM returns an unrecognizable or invalid classification, the memo appears in the Alerts view with a description of the unexpected response

---

### US-07 — Menu bar presence
As a user,
I want to access Settings, Alerts, and Quit from a menu bar icon,
so that the app stays out of my way but remains accessible.

**Acceptance Criteria**
- [ ] AC-07.1: The app displays an icon in the macOS menu bar
- [ ] AC-07.2: Clicking the icon shows exactly three options: Settings, Alerts, Quit
- [ ] AC-07.3: Selecting Quit terminates the background daemon
- [ ] AC-07.4: The app does not appear in the Dock or the Cmd+Tab app switcher

---

### US-08 — Configurable classification prompt
As a user,
I want to customize the LLM prompt used for classification and specify target destinations,
so that I can tune the system's behavior and route memos to specific lists, calendars, and folders.

**Acceptance Criteria**
- [ ] AC-08.1: The Settings interface exposes an editable text field for the classification prompt
- [ ] AC-08.2: The Settings interface allows selecting a target Reminders list, Calendar, and Notes folder
- [ ] AC-08.3: Changes to settings take effect for the next memo processed without requiring a restart

---

### US-09 — Deduplication by filename
As a user,
I want the system to never process the same voice memo file twice,
so that I do not end up with duplicate reminders, events, or notes.

**Acceptance Criteria**
- [ ] AC-09.1: After a memo file is processed (or skipped due to no transcript), its filename is stored locally
- [ ] AC-09.2: A file with a previously-recorded filename is not processed again
- [ ] AC-09.3: Two different files with identical transcript content are each processed independently

---

## Routing Rules

| Classified Intent | Destination | Default Destination |
|---|---|---|
| Task | Apple Reminders | System default list |
| Calendar event | Apple Calendar | System default calendar |
| Reference material | Apple Notes | Default folder |

- Duration for calendar events defaults to 30 minutes when not specified in the transcript.
- Notes receive an LLM-generated title and summary, not the raw transcript.

---

## Edge Cases

- **Voice memo with no transcript**: Silently skipped; filename recorded to prevent re-examination; no alert surfaced.
- **LLM unreachable at processing time**: Memo is queued; automatic retry when LLM becomes available; no alert surfaced.
- **Apple Reminders/Calendar/Notes API call fails**: Memo appears in Alerts with reason; no automatic retry.
- **Transcript with ambiguous or unparseable date/time for a calendar event**: Memo appears in Alerts with a description of the ambiguity.
- **Same filename encountered again (duplicate file)**: Skipped entirely — no processing, no alert.
- **Two different files with identical transcript content**: Both processed independently as separate items.
- **LLM returns an unrecognizable classification**: Treated as a failure; memo appears in Alerts with a description of the unexpected response.
- **Voice memo file arrives while the app is not running**: Picked up on next launch when the watched location is scanned.
- **Settings changed while memos are queued**: Queued memos are processed using the settings in effect at the time of processing, not at the time of queuing.
- **Extremely long transcript**: Processed as-is up to the LLM's context limit; if the LLM rejects it, treated as a failure and surfaced in Alerts.

---

## Success Criteria

1. Voice memos with embedded transcripts that sync to the Mac are routed to the correct destination as classified by the LLM, with zero items silently lost or dropped.
2. Zero memos lost due to transient LLM unavailability — all queued memos are eventually processed after the LLM recovers.
3. Zero duplicate items created from the same voice memo file.
4. Time from voice memo sync to item creation is under 30 seconds during normal operation (LLM available, APIs responsive). This is a target benchmark, not a hard requirement.

---

## Dependencies & Assumptions

**Dependencies**
- Apple Voice Memos must sync audio files to a known location on macOS
- Apple must embed transcripts in voice memo file metadata (available as of recent macOS/iOS versions)
- A local LLM must be running and accessible on the same machine (technology-agnostic — any local inference server)
- Apple Reminders and Calendar must be accessible via system APIs for creating items
- Apple Notes must be writable via some local mechanism (specific approach to be determined in architecture)

**Assumptions**
- The user is running macOS 15 (Sequoia) or later
- The user has a single macOS account (no multi-user scenarios)
- Voice memos recorded on any Apple device (iPhone, Watch, Mac) sync to the Mac via iCloud
- Apple's embedded transcript is plain text sufficient for LLM classification (no audio re-processing needed)
- The local LLM can reliably classify short natural-language transcripts into three categories (task, event, reference)
- File system monitoring or periodic scanning is sufficient to detect new voice memos

---

## Open Questions

- [ ] What is the reliable mechanism for writing to Apple Notes? (Reminders and Calendar have well-known system APIs, but Notes lacks a direct equivalent — an alternative approach may be needed.)
  - Decision needed by: architecture phase
- [ ] What is the exact file path or directory where Voice Memos sync on macOS?
  - Decision needed by: architecture phase
- [ ] What metadata field in the voice memo file contains the embedded transcript, and is it accessible via public APIs?
  - Decision needed by: architecture phase

---

## Out of Scope (Clarification)

- **Local speech-to-text fallback** — discussed as a way to handle memos without transcripts, but excluded to keep the pipeline simple and avoid bundling large models. If Apple's transcript is missing, the memo is silently skipped.
- **Manual retry on failed alerts** — discussed for completeness, but excluded to keep the Alerts view read-only and avoid building retry/state-machine UI. Users can re-record the memo if needed.
- **Preserving raw transcript in created items** — discussed as a debugging aid, but excluded to keep created items clean. Notes get a summary, not a transcript dump.
- **Full windowed macOS application** — discussed early on, but excluded in favor of a minimal menu-bar-only presence to keep the app unobtrusive.
