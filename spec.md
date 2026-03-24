# Utterd Spec

**Date**: 2026-03-24
**Status**: Draft
**Author**: Dave

---

## Why This Exists

Capturing ideas, tasks, and events by voice is low friction, but the recordings accumulate untriaged — never reaching the systems (Reminders, Calendar, Notes) where they would actually be useful. For productivity-minded people who rely on trusted systems to manage commitments, every untriaged voice memo is a commitment at risk of being forgotten. The gap between capture and triage is entirely manual today, and that manual step is the reason memos pile up.

---

## Scope

### In
- Monitor `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings` for new voice memo recordings
- Extract the embedded transcript from voice memo audio files
- Copy memo files to a temporary location for processing
- Deduplicate processing: track which files have been processed and skip them on subsequent runs
- Classify each transcript as a reminder, calendar event, or note using a language model
- Extract structured data from the transcript (target list/calendar/folder, dates, times, content) using a language model
- Discover existing lists, calendars, and folders at runtime from Reminders, Calendar, and Notes
- Create items in Reminders, Calendar, and Notes via system APIs
- Route items to a default list/calendar/folder when no routing rule matches
- Natural-language routing rules defined in a YAML configuration file
- macOS Foundation Model framework (available on macOS 26+) as the default language model provider
- OpenAI-compatible remote endpoint as a fallback language model provider
- Menu bar presence with a service status indicator
- Settings accessible from the menu bar: language model provider, enabled services, launch at login
- Alerts list accessible from the menu bar showing failed processing attempts
- Quit option from the menu bar

### Out (explicitly)
- Mobile app — this is a desktop-only daemon
- Graphical editor for routing rules — rules are edited as text in a YAML configuration file
- Transcript generation from audio (speech-to-text) — v1 depends on transcripts already embedded in the audio file
- Automatic retry of failed operations — failures are logged, not retried
- Multiple user profiles or accounts — single-user tool
- Full windowed application UI — interaction is limited to the menu bar
- Remote telemetry or analytics — all data stays local

---

## User Stories

### US-00 — North Star: Hands-free voice memo triage
As a productivity-minded person,
I want my voice memos to automatically appear as the correct item in Reminders, Calendar, or Notes without any manual intervention,
So that I can trust voice capture as a reliable front door to my productivity system.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-00.1: A voice memo recorded on a phone and synced to the computer appears as a reminder, calendar event, or note in the correct app within 5 minutes of the file arriving on disk
- [ ] AC-00.2: The created item contains the meaningful content of the original memo (title, body, date/time as applicable)
- [ ] AC-00.3: No manual step is required between recording the memo and the item appearing in the destination app
- [ ] AC-00.4: The same memo is never processed twice, even if the daemon restarts

---

### US-01 — First run: Granting permissions and validating prerequisites
As a new user,
I want clear feedback on what the app needs to function and what is missing,
So that I can complete setup without guessing.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-01.1: On first launch, if the required disk access permission has not been granted, the app surfaces a message explaining the permission is needed and how to grant it
- [ ] AC-01.2: If the voice memo sync directory does not exist or is inaccessible, an alert appears in the alerts list explaining the issue
- [ ] AC-01.3: If no language model provider is available (neither on-device nor remote), an alert appears stating that memos cannot be processed until a provider is configured
- [ ] AC-01.4: Once prerequisites are satisfied, the status indicator in the menu bar shows the service as active with no further user action

---

### US-02 — Automatic file detection
As a user,
I want the app to detect new voice memos as soon as they appear in the sync directory,
So that I do not need to trigger processing manually.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-02.1: When a new audio file appears in `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`, the app begins processing it automatically
- [ ] AC-02.2: Files that existed in the directory before the app launched are evaluated against the deduplication store and processed only if new
- [ ] AC-02.3: If the watched directory is removed or becomes inaccessible while the app is running, an alert is surfaced in the alerts list

---

### US-03 — Transcript extraction
As a user,
I want the app to read the transcript embedded in my voice memo,
So that the content can be classified and routed without me typing anything.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-03.1: The app extracts the embedded transcript from a supported audio file without modifying the original file
- [ ] AC-03.2: If a memo has no embedded transcript, the memo is skipped and an entry appears in the alerts list identifying the file and the reason
- [ ] AC-03.3: The original audio file in the sync directory is never modified or deleted

---

### US-04 — Classification and data extraction
As a user,
I want each memo to be automatically classified as a reminder, calendar event, or note and have relevant details extracted,
So that the item is created with the right type and content.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-04.1: Each transcript is classified into exactly one category: reminder, calendar event, or note
- [ ] AC-04.2: For reminders, the extracted data includes at minimum a title; optionally a due date and target list
- [ ] AC-04.3: For calendar events, the extracted data includes at minimum a title and date/time; optionally a target calendar and duration
- [ ] AC-04.4: For notes, the extracted data includes at minimum a title and body; optionally a target folder
- [ ] AC-04.5: If the language model returns an unrecognizable or ambiguous classification, the memo is routed to Notes as a default
- [ ] AC-04.6: If the language model call fails entirely, the memo is logged in the alerts list and skipped

---

### US-05 — Routing rules
As a user,
I want to define natural-language rules in a YAML configuration file that control where items are routed,
So that memos about specific topics land in the right list, calendar, or folder automatically.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-05.1: The app reads routing rules from a YAML configuration file on startup and when the file changes
- [ ] AC-05.2: Each rule maps a natural-language condition to a destination (a specific list, calendar, or folder)
- [ ] AC-05.3: When a memo matches a rule, the item is created in the destination specified by that rule
- [ ] AC-05.4: When no rule matches, the item is created in the default list, calendar, or folder for its category
- [ ] AC-05.5: If the YAML configuration file is missing or malformed, the app uses defaults for all routing and surfaces a warning in the alerts list

---

### US-06 — Item creation in destination apps
As a user,
I want reminders, calendar events, and notes to be created in the correct app with the extracted content,
So that my voice memos become actionable items in my existing workflow.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-06.1: A classified reminder results in a new item in Reminders with the extracted title, due date (if any), and target list
- [ ] AC-06.2: A classified calendar event results in a new event in Calendar with the extracted title, start time, duration (if any), and target calendar
- [ ] AC-06.3: A classified note results in a new note in Notes with the extracted title, body, and target folder
- [ ] AC-06.4: If creation fails (e.g., the target list/calendar/folder does not exist), the app falls back to the default destination for that category
- [ ] AC-06.5: If creation still fails after fallback, the failure is logged in the alerts list with the memo identity and error reason

---

### US-07 — Deduplication
As a user,
I want each voice memo to appear exactly once in my productivity system, even if the app restarts or duplicate file events occur,
So that my systems stay clean and trustworthy.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-07.1: After a memo is successfully processed, it is recorded in a local deduplication store
- [ ] AC-07.2: If the same file appears again (same event, app restart, or re-sync), it is skipped without processing
- [ ] AC-07.3: The deduplication store persists across app restarts

---

### US-08 — Language model provider selection
As a user,
I want to choose between an on-device language model and a remote endpoint,
So that I can use whichever provider is available or preferred.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-08.1: The settings menu allows selecting between the on-device model and a remote endpoint
- [ ] AC-08.2: When the on-device model is selected but unavailable, an alert is surfaced and processing pauses
- [ ] AC-08.3: When the remote endpoint is selected, the app uses the configured endpoint URL and credentials
- [ ] AC-08.4: Switching providers takes effect for the next memo processed, without requiring an app restart
- [ ] AC-08.5: When the user selects or configures a remote endpoint, a notice is displayed stating that transcript text will be sent to the configured server

---

### US-09 — Menu bar status and alerts
As a user,
I want to see at a glance whether the service is running and whether anything has failed,
So that I can trust the system is working or know when it needs attention.

**Priority**: Must

**Acceptance Criteria**
- [ ] AC-09.1: The menu bar icon indicates whether the service is active, idle, or in an error state
- [ ] AC-09.2: The menu bar dropdown shows a list of recent alerts (failed processing attempts)
- [ ] AC-09.3: Each alert identifies the memo file, the failure stage, and the reason
- [ ] AC-09.4: The dropdown includes a quit option that stops the daemon cleanly
- [ ] AC-09.5: The status indicator transitions to an error state after 10 or more consecutive processing failures, and returns to active when a memo is processed successfully

---

### US-10 — Failure logging
As a user,
I want all processing failures to be logged persistently,
So that I can review what went wrong even after restarting the app.

**Priority**: Should

**Acceptance Criteria**
- [ ] AC-10.1: Every processing failure (transcript extraction, classification, item creation) is written to a persistent local log
- [ ] AC-10.2: The log is human-readable and includes timestamps, file identifiers, failure stage, and error details
- [ ] AC-10.3: The alerts list in the menu bar reflects the contents of this log

---

### US-11 — Launch at login
As a user,
I want the option to start the app automatically when I log in,
So that I do not need to remember to launch it manually.

**Priority**: Should

**Acceptance Criteria**
- [ ] AC-11.1: A toggle in settings enables or disables launch at login
- [ ] AC-11.2: When enabled, the app starts in the background on login with no visible window
- [ ] AC-11.3: When disabled, the app does not start on login

---

## Pipeline Stages

The processing pipeline for each voice memo follows these stages in order:

| Stage | Input | Output | Failure behavior |
|---|---|---|---|
| Detection | New file in watched directory | File path queued for processing | Alert if directory inaccessible |
| Copy | Original file path | Temporary copy for safe processing | Skip memo, log alert |
| Transcript extraction | Temporary audio file | Plain text transcript | Skip memo, log alert |
| Classification | Transcript text | Category (reminder / event / note) | Skip memo, log alert |
| Data extraction | Transcript text + category | Structured fields (title, date, list, etc.) | Skip memo, log alert |
| Routing | Structured fields + routing rules | Target destination (specific or default) | Fall back to default destination |
| Item creation | Structured fields + destination | Item in Reminders, Calendar, or Notes | Log alert, skip memo |
| Deduplication record | Successful processing | Entry in deduplication store | — |

---

## Edge Cases

- **Memo with no embedded transcript**: Skip the memo. Log an alert identifying the file and stating no transcript was found.
- **Very long transcript exceeding language model input limits**: Truncate the transcript to fit within the provider's limits. Process with the truncated input. Log a warning if truncation occurred.
- **Duplicate file system events for the same file**: The deduplication store prevents reprocessing. The second event is silently ignored.
- **Watched directory does not exist (sync not configured)**: Surface an alert on startup and periodically. Do not crash. Resume automatically if the directory appears later.
- **Language model returns ambiguous or unrecognizable classification**: Route the memo to Notes as the default category.
- **Target list, calendar, or folder referenced by a routing rule no longer exists**: Fall back to the default destination for that category. Log a warning.
- **Configuration file is edited while the app is running**: Reload rules and apply them to subsequent memos. Do not reprocess already-processed memos.
- **Multiple memos arrive simultaneously**: Process them sequentially. Ordering does not need to match file creation order, but all must be processed.
- **App is quit and relaunched**: On relaunch, scan the directory, check each file against the deduplication store, and process only new files.
- **Disk is full and deduplication store cannot be written**: Log an alert. Do not process additional memos until the store can be updated (to prevent duplicates).
- **Remote language model endpoint is unreachable**: Log an alert. Do not process memos. Resume automatically when the endpoint becomes reachable.

---

## Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Performance** | End-to-end processing of a single memo (from file detection to item creation) completes in under 30 seconds, excluding network latency for remote language model calls. |
| **Latency (end-to-end)** | A voice memo appears as the correct item within 5 minutes of the file arriving in the sync directory on disk. |
| **Privacy** | When the on-device language model is used, no memo content leaves the machine. When a remote endpoint is used, the user is informed during configuration that transcript text will be sent to the configured server (see AC-08.5). |
| **Security** | Credentials for remote language model endpoints are stored in the system keychain, not in plaintext configuration files. The app accesses only the directories and APIs it needs, despite having broad disk access permission. |
| **Persistence** | The deduplication store and failure log persist across app restarts. Growth is bounded: entries older than 90 days may be pruned automatically. |
| **Startup / lifecycle** | The app launches as a background agent (no dock icon, no main window). On launch it validates prerequisites, begins watching for files, and processes any unprocessed backlog. After a crash, relaunch and deduplication store ensure no duplicates and no missed memos. |
| **Failure thresholds** | Each memo is attempted once. A failure at any pipeline stage results in a logged alert and the memo is skipped — no automatic retry. If 10 or more consecutive failures occur, the status indicator changes to an error state (see AC-09.5). |
| **Supported environment** | Requires macOS 15 (Sequoia) or later. On-device language model (macOS Foundation Model framework) requires macOS 26 (Tahoe) or later. On macOS 15–25, the on-device model is unavailable; the app requires a configured remote endpoint to process memos and will surface an alert if no provider is available. |
| **Reliability** | The app should remain running indefinitely without memory leaks or resource exhaustion. It must survive directory changes, language model unavailability, and API failures without crashing. |

---

## Success Criteria

1. A voice memo recorded on a phone appears as the correct item (reminder, event, or note) in the correct destination app within 5 minutes of the file syncing to the computer — verified across 20 consecutive memos with zero misses (traces to US-00, US-02, US-04, US-06).
2. Zero duplicate items are created from the same voice memo across 50 test runs including app restarts and simulated duplicate file events (traces to US-07).
3. Zero manual intervention is required after initial setup — the user records a memo and the item appears without touching the computer (traces to US-00, US-01).
4. 100% of processing failures appear in the alerts list with an identifiable file name and failure reason within 10 seconds of the failure (traces to US-09, US-10).
5. Routing rules correctly direct memos to specified destinations for at least 95% of memos that match a rule, verified across a test set of 20 memos with varying topics (traces to US-05, US-06).

> **Note on transitive coverage:** Success criteria 1 and 3 transitively validate transcript extraction (US-03) and provider selection (US-08) as prerequisite capabilities — a memo cannot be processed end-to-end without both functioning correctly.

---

## Dependencies & Assumptions

**Dependencies**
- System APIs for programmatic creation of reminders and calendar events (EventKit — established platform API)
- A mechanism for programmatic creation of notes in the Notes app (historically limited; may require scripting bridge)
- macOS Foundation Model framework API availability on macOS 26+
- File system event monitoring capability provided by the operating system (FSEvents)
- Voice memos synced to the local file system via iCloud sync

**Assumptions**

| Assumption | Validation | Fallback if false |
|---|---|---|
| Voice memos recorded on a phone sync to `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings` on the computer | Known iCloud sync behavior; verified on current OS versions | App surfaces an alert; does nothing if directory is empty or missing |
| Voice memo audio files contain embedded transcripts | Tested on recent OS versions; transcripts are generated on-device during recording | v1 skips memos without transcripts and logs an alert; transcript generation is deferred to a future version |
| The macOS Foundation Model framework on macOS 26 is available to apps with broad disk access (unsandboxed) | Based on public platform announcements | User configures a remote language model endpoint instead |
| System APIs allow programmatic item creation in Reminders and Calendar | Established APIs (EventKit); well-documented | Surface error in alerts list |
| Notes can be created programmatically with folder targeting | Historically possible via scripting bridge; less well-documented | Surface error in alerts; investigate alternative approaches |
| Tech preferences: the project uses Swift 6.2, SwiftUI, strict concurrency, XcodeGen, local Swift package modularization, and Swift Testing | Team convention | N/A — these are project decisions, not runtime assumptions |

---

## Open Questions

- [ ] What is the exact format and location of the embedded transcript within voice memo audio files?
  - Decision needed by: before implementing transcript extraction (first development sprint)
- [ ] Is the macOS Foundation Model framework available to unsandboxed (non-App-Store) apps?
  - Decision needed by: before finalizing language model provider abstraction
- [ ] What are the limitations of programmatic access to Notes — can specific folders be targeted, and what content formatting is supported?
  - Decision needed by: before implementing Notes integration
- [ ] Where should the deduplication store live, and what format should it use? (e.g., Application Support directory, lightweight database, flat file)
  - Decision needed by: before implementing deduplication
- [ ] Where should the YAML routing rules configuration file live? (e.g., Application Support, ~/.config, or alongside the app)
  - Decision needed by: before implementing configuration loading
- [ ] What is the maximum transcript length the on-device language model can accept, and how should truncation be handled?
  - Decision needed by: before implementing classification

---

## Out of Scope (Clarification)

These items were discussed during requirements gathering and explicitly deferred:

- **UI-based routing rule editor** — the text-based YAML configuration file is sufficient for the initial audience (the developer and power users). May be added in a future version if adoption grows beyond technical users.
- **Transcript fallback via speech-to-text** — some older memos may lack embedded transcripts. Deferred to reduce v1 complexity. V1 skips memos without transcripts.
- **Retry / reprocessing of failed memos** — deferred because the primary user can manually re-record or check the alerts list. A future version may add a "reprocess" action from the alerts list.
