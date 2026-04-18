# Utterd — Project Spec

**Last updated**: 2026-04-18
**Last verified**: 2026-04-18
**Status**: Active

> This spec represents current state, not aspirational state. Update it whenever
> implementation changes. The "Current State" section is the most important — keep it accurate.

---

## Table of Contents

- [Current State](#current-state)
- [What This Project Does](#what-this-project-does)
- [Architecture Overview](#architecture-overview)
- [Architecture Decisions](#architecture-decisions)
- [Testing Strategy](#testing-strategy)
- [Deployment & Infrastructure](#deployment--infrastructure)
- [Boundaries & Constraints](#boundaries--constraints)
- [Gotchas](#gotchas)
- [Ownership](#ownership)
- [Known Issues](#known-issues)
- [Tech Debt](#tech-debt)

---

## Current State

Shipped as v1.1.0 (2026-04-18). The end-to-end pipeline is wired and running on macOS 26+: an `FSEventsDirectoryMonitor` watches `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings` for new `.m4a` and `.qta` files (1024-byte minimum, iCloud placeholder filtering via `VoiceMemoQualifier`). `PipelineController` drains any unprocessed records from `JSONMemoStore` on startup, then processes each record sequentially through `TranscriptionPipelineStage` (`SpeechAnalyzerTranscriptionService`) → optional `NoteRoutingPipelineStage` (which invokes `IterativeRefineSummarizer` + `FoundationModelLLMService` when enabled, then `AppleScriptNotesService` to create the note) → dedup mark in the store. Failures are recorded as `markFailed` and not retried.

The UI shell is complete: `MenuBarExtra` shows last-processed timestamp plus Settings/Quit; the Settings window offers default Notes folder selection, summarization toggle with custom instructions, title generation toggle, launch-at-login via `SMAppService.mainApp`, "Open Log File" for `utterd.log`, and an About section with version + GitHub releases link. On launch, `evaluatePermissionGate` checks the Voice Memos directory exists, attempts a listing (to register the app for Full Disk Access TCC), and either proceeds, shows the FDA alert, or shows the "Voice Memos Not Set Up" alert. Toggling summarization or title generation probes `FoundationModelLLMService` — if Apple Intelligence is unavailable, the toggle reverts and the user is linked to System Settings. A signed + notarized DMG is built via `scripts/build-release.sh`; CI runs build + test on every PR via GitHub Actions (`macos-15` runner).

**Not yet implemented:**
- **Remote LLM provider** — `LLMService` protocol exists but `FoundationModelLLMService` is the only concrete implementation. No remote fallback when Apple Intelligence is unavailable.
- **Keychain credential storage** — architecturally decided for a future remote provider, but no code path consumes it today.
- **Rich-text/HTML note content** — Notes are created as plain text via AppleScript; formatting is unexplored.
- **Automatic retries** — failed memos are marked once and left; no retry scheduler.
- **macOS 15–25 fallback** — on older macOS, `startPipeline()` logs a warning and exits. Memos are not processed until the user upgrades to macOS 26+.

---

## What This Project Does

Utterd is a macOS menu bar daemon that turns voice memos into Apple Notes without manual steps. It watches the iCloud Voice Memos sync directory, transcribes new recordings on-device, optionally summarizes and titles them with an on-device language model, and files the result in a user-chosen Notes folder. Built for a single developer (and, eventually, open-source users) who wants frictionless voice capture and never wants to think about where a memo went.

**Privacy posture:** everything runs on-device. No memo content, telemetry, or analytics leaves the machine.

---

## Architecture Overview

```
iCloud Sync ──▶ FSEventsDirectoryMonitor ──▶ VoiceMemoWatcher ──▶ MemoConsumer ──▶ JSONMemoStore
   (.m4a/.qta)                                     │                                    │
                                                   ▼                                    ▼
                              TranscriptionPipelineStage                        (dedup, drain)
                              (SpeechAnalyzerTranscriptionService)                       │
                                                   │                                    │
                                                   ▼                                    │
                              NoteRoutingPipelineStage ◀──────────── PipelineController ◀┘
                              │                                      (sequential processing)
                              ├─ IterativeRefineSummarizer (optional)
                              ├─ FoundationModelLLMService (optional title/summary)
                              └─ AppleScriptNotesService ──▶ Apple Notes
```

Processing is sequential and immediate — one memo at a time, no polling. Unprocessed records from prior sessions are drained before new watcher events. Records are `markFailed` on transcription or routing failure and left alone otherwise.

**Key components:**
- `Libraries/Sources/Core/` — all pipeline logic, protocols, and persistence. Pure Swift, testable without Xcode via `swift test`.
- `Utterd/App/AppDelegate.swift` — composition root: wires `FSEventsDirectoryMonitor` → `VoiceMemoWatcher` → `PipelineController` with concrete services.
- `Utterd/Core/` — app-only concrete service implementations (`SpeechAnalyzerTranscriptionService`, `FoundationModelLLMService`, `AppleScriptNotesService`, `UserSettings`).
- `Utterd/Features/MenuBar/` and `Utterd/Features/Settings/` — SwiftUI views and `@Observable` view models.

### Shared External Dependencies

| Dependency | Normal Behavior | Failure Behavior | Constraints / Can't Do |
|------------|-----------------|------------------|------------------------|
| iCloud Voice Memos directory | FSEvents delivers file creation events for new `.m4a`/`.qta` | If directory missing at launch, app shows "Voice Memos Not Set Up" alert and terminates | Path is undocumented Apple internal (`group.com.apple.VoiceMemos.shared`); requires Full Disk Access; may change between macOS versions |
| `SpeechAnalyzer` (macOS 26+) | On-device speech-to-text on a temp copy of the audio | `TranscriptionPipelineStage` returns nil; record `markFailed` with "Transcription failed" | Unavailable < macOS 26; no streaming; no speaker diarization |
| Foundation Model (Apple Intelligence) | On-device LLM for summarization + title generation | Toggles probe the model; if unavailable, revert toggle and link to System Settings | Requires Apple Intelligence enabled; context budget enforced by `LLMContextBudget` (3000 words total, 200 system overhead, 30% summary reserve); no guarantee of availability for unsandboxed apps |
| Apple Notes via `NSAppleScript` | Creates plain-text notes in the user-selected folder | `NoteRoutingPipelineStage` returns `.failure(reason)`; record `markFailed` | Requires Automation permission; plain text only; folder targeting by name + ID; prompt-injection hardening lives in `AppleScriptEscaping` |
| `SMAppService.mainApp` | Registers the app as a login item when "Launch at Login" is toggled | Toggle state re-syncs from system status on view appear | User can disable in System Settings independently — UI must reflect actual state, not stored preference |

**Degraded mode:** on macOS 15–25, or if Apple Intelligence is off, the pipeline either doesn't start or runs without the LLM stage (full transcript is written to Notes unmodified).

---

## Architecture Decisions

| Decision | Rationale | Date | Alternatives Considered |
|----------|-----------|------|-------------------------|
| XcodeGen over committed `.xcodeproj` | Project will be open-sourced — human-readable, diffable, merge-conflict-free | 2026-03-24 | Committed `.xcodeproj` — rejected for poor OSS contributor experience |
| Local SPM package (`Libraries/Core`) for pipeline logic | Isolates core logic from app target; enables fast `swift test` without Xcode | 2026-03-24 | Everything in app target — rejected for lack of modularity and slow tests |
| Swift 6.2 strict concurrency (`complete`) | Eliminates data races at compile time; required by Foundation Model framework | 2026-03-24 | Relaxed concurrency — rejected, doesn't catch bugs early enough |
| SwiftUI `MenuBarExtra` over AppKit `NSStatusItem` | Native SwiftUI integration, less boilerplate, aligns with `@Observable` | 2026-03-24 | AppKit `NSStatusItem` — rejected unless SwiftUI proves insufficient |
| `@Observable` over `ObservableObject` | Per-property view invalidation, less boilerplate, modern pattern | 2026-03-24 | `ObservableObject` + `@Published` — legacy |
| `NSAppleScript` for Notes | Only known mechanism for programmatic Notes access with folder targeting | 2026-03-24 | Scripting Bridge — rejected; avoids generated bridge headers and App Store entitlements |
| Sequential pipes-and-filters pipeline | Simple, debuggable, exactly-once via dedup store checked before + written after | 2026-03-24 | Concurrent stage fan-out — rejected as over-engineered for single-user throughput |
| Keychain for remote LLM credentials (deferred) | macOS security standard — avoids plaintext secrets. No remote provider implemented yet. | 2026-03-24 | Plaintext YAML — rejected |
| LLM toggle probes model availability | Immediate feedback beats silent fallback when Apple Intelligence is off | 2026-04-18 | Run-time detection inside pipeline only — rejected; user would flip toggle then see nothing |

---

## Testing Strategy

**Framework:** Swift Testing (`@Suite`, `@Test`, `#expect`). XCTest tolerated only in legacy files.
**Location:** `UtterdTests/` for app-level tests; `Libraries/Tests/CoreTests/` for pipeline/library tests.
**Naming:** test structs named `[Subject]Tests`; test functions describe the behavior.

**Test types:**
- **Library unit tests:** `cd Libraries && timeout 120 swift test </dev/null` — fast, no Xcode.
- **App unit + integration tests:** `xcodebuild -scheme Utterd -destination 'platform=macOS' test`.
- **AppleScript integration tests** (`AppleScriptNotesServiceIntegrationTests`, `AppleScriptNotesServiceFolderIntegrationTests`) are **skipped in CI** — they require an authorized Notes.app session and a signed runner. Run them locally before shipping changes to `AppleScriptNotesService`.

**Conventions:**
- `@MainActor` on test functions that touch `@MainActor`-isolated types.
- Arrange → Act → Assert with `#expect`.
- `AppDelegate.applicationDidFinishLaunching` short-circuits when `XCTestConfigurationFilePath` is set — tests don't trigger the permission gate.

---

## Deployment & Infrastructure

**CI/CD:** GitHub Actions — `.github/workflows/build.yml` runs on every PR to `main` on a `macos-15` runner. Steps: install XcodeGen via brew, write an empty `DEVELOPMENT_TEAM` into `Local.xcconfig`, `xcodegen generate`, `xcodebuild build`, `xcodebuild test` (with AppleScript integration tests excluded).

**Release:** manual via `scripts/build-release.sh`. Produces a signed + notarized DMG with a styled installer (app icon + Applications alias). Released to GitHub Releases. See `docs/releasing.md` for the checklist (including `brew install create-dmg` prerequisite).

**Runtime:** user installs the signed DMG, drags to Applications, grants Full Disk Access and Automation permissions on first launch.

**No staging environment** — single-user app.

---

## Boundaries & Constraints

### Always Do
- Run `xcodegen generate` after modifying `project.yml`, before building.
- Run build + test before opening a PR: `xcodebuild -scheme Utterd -destination 'platform=macOS' build test`.
- Use Swift Testing (`@Test`, `#expect`) for new tests.
- Use `@Observable` for new models.
- Read from temporary copies of voice memo files, never the originals.
- Check the dedup store before processing; mark after successful creation.
- Update CHANGELOG.md on behavior-visible changes.
- Update this spec's Current State after any significant implementation change.

### Ask First
- Before adding third-party SPM dependencies (the project minimizes deps for OSS simplicity).
- Before changing the pipeline stage order or adding/removing stages.
- Before modifying `project.yml` target structure or build settings.
- Before dropping to AppKit (`NSViewRepresentable`) — SwiftUI first.
- Before changing the `LLMService`, `TranscriptionService`, `NotesService`, or `MemoStore` protocols.
- If a pattern, dependency, or architectural decision isn't covered by this spec, ask before inferring — don't invent conventions.

### Never Do
- Never modify or delete original voice memo files in the sync directory.
- Never store credentials in plaintext config files.
- Never skip the dedup store check.
- Never process memos when the dedup store cannot be written (prevents disk-full duplicates).
- Never send telemetry, analytics, or memo content off the machine.
- Never run `swift build` or `swift test` concurrently — SwiftPM holds an exclusive lock on `.build/`.

---

## Gotchas

- **Launch-at-login state is authoritative from the system, not UserDefaults.** `SMAppService.mainApp.status` can diverge from the stored preference (user disables it in System Settings). The Settings view re-syncs on appear — any new code reading `launchAtLogin` should do the same.
- **`evaluatePermissionGate` deliberately triggers a listing** even if `directoryExists` passes, so the app appears in System Settings > Full Disk Access. Don't "optimize" the redundant call away.
- **Dedup key is the file URL**, not content hash. If iCloud re-uploads a memo with a new filename, it will be re-processed. Acceptable for now — do not change without considering migration of existing `JSONMemoStore` entries.
- **AppleScript injection is a real threat model.** Transcripts can contain arbitrary user speech. All transcript content passed to AppleScript goes through `AppleScriptEscaping`; any new AppleScript call site must use it.
- **Foundation Model availability for unsandboxed apps is unconfirmed at the framework level.** The toggle probe is the only reliable signal; don't assume availability from macOS version alone.
- **`.qta` vs `.m4a`:** both are voice memo formats iCloud may produce. Both paths share the same 1024-byte floor and placeholder filter (`VoiceMemoQualifier`). New formats must go through the same qualifier, not a parallel check.
- **Tests that touch Notes.app (`AppleScriptNotesServiceIntegrationTests`, `...FolderIntegrationTests`) are excluded from CI** — changes to `AppleScriptNotesService` must be run locally before merge.

---

## Ownership

- **Contact:** GitHub issues at <https://github.com/DaveBben/utterd/issues>

---

## Known Issues

- **`SettingsRoutingModelTests` and `MockTranscriptionService` use `fatalError()`** for unused protocol methods — acceptable for now, but surfaces as a crash if a refactor accidentally invokes them.

---

## Tech Debt

- `AppDelegate.showPermissionAlert` is not covered by tests because it constructs `NSAlert` inline. Tracked via TODO in `AppDelegate.swift:208` — refactor to injectable closures like `showDirectoryMissingAlert` for parity.
- No retry scheduler. `markFailed` records sit forever.
- CHANGELOG is maintained manually. No automation ties PR titles to changelog entries.
