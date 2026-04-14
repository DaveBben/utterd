# Utterd — Project Spec

**Last updated**: 2026-04-01
**Status**: Draft

---

## What This Project Does

Utterd is a macOS menu bar daemon that automatically turns voice memos into Apple Notes. It monitors the iCloud Voice Memos sync directory, transcribes audio on-device (macOS 26+), and uses a language model to pick the right Notes folder (summarization is supported but not yet enabled) — no manual intervention after setup. Built for a single user who wants frictionless voice capture without thinking about where things go.

---

> **Note:** Tech Stack, Directory Structure, and Development Commands belong in CLAUDE.md,
> not in SPEC.md. Do not duplicate them here — the project spec covers context that goes
> beyond what CLAUDE.md provides.

---

## Project Goals

- Ship a working end-to-end pipeline: voice memo file appears on disk → note shows up in the right Apple Notes folder within 5 minutes, zero manual steps
- Every memo processed exactly once — no duplicates, no misses, even across restarts and duplicate file events
- Privacy by default: on-device LLM (macOS 26+) for all processing — no memo content leaves the machine
- Eventually open-source the project — codebase must be clean, self-documenting, and easy for outside contributors to build and run

---

## Quality Goals

| Priority | Goal | Rationale |
|----------|------|-----------|
| 1 | Reliability | A missed or duplicated memo erodes trust in the entire system — the user must never wonder "did that memo make it?" |
| 2 | Privacy | Voice memos contain personal content; on-device processing is the default. Remote use requires informed consent |
| 3 | Maintainability | Single developer, eventual open-source — code must be easy to understand and modify without tribal knowledge |
| 4 | Operability | Every failure must be visible (menu bar alerts + persistent log) so the user knows when the system needs attention |

---

## Non-Functional Requirements

- **Performance**: End-to-end processing of a single memo completes in under 60 seconds, excluding iCloud sync time
- **Privacy**: On-device LLM → no memo content leaves the machine
- **Security**: LLM prompts must be hardened against injection from transcript content
- **Persistence**: Deduplication store and failure log survive app restarts. Entries older than 90 days may be pruned automatically
- **Failure thresholds**: Each memo attempted once. No automatic retry. 10+ consecutive failures → error state in status indicator
- **Reliability**: App must run indefinitely without memory leaks or resource exhaustion. Must survive directory changes, LLM unavailability, and API failures without crashing

---

## Architecture Summary

```
iCloud Sync ──▶ [File Watcher] ──▶ [Transcribe] ──▶ [LLM: summarize/title] ──▶ Apple Notes
  (.m4a / .qta files)                  (on-device)      (on-device)        (AppleScript)
                                                    On-device Foundation Model (macOS 26+)
```

**Key design patterns:**
- Sequential pipes-and-filters pipeline — detection → copy → transcription → optional summarization and title generation → note creation → dedup → cleanup. Each stage is an isolated function with typed inputs/outputs
- Protocol-based LLM provider abstraction — a Swift protocol defines the LLM interface; the on-device Foundation Model is the only concrete provider today. The protocol enables adding a remote variant later
- Exactly-once processing via persistent dedup store — checked before processing, written after successful creation

**Data flow:**
A new .m4a or .qta file arrives in the watched directory → copied to a temp location → audio transcribed via on-device speech-to-text → transcript optionally summarized and titled by on-device LLM → note created in Apple Notes via AppleScript → file identity recorded in dedup store → temp copy cleaned up. On macOS 15–25, the pipeline does not start; memos are not processed until the user upgrades to macOS 26+.

---

## Architecture Decisions

| Decision | Rationale | Date | Alternatives Considered |
|----------|-----------|------|------------------------|
| XcodeGen over committed .xcodeproj | Project will be open-sourced — keeps project definition human-readable, diffable, and merge-conflict-free | 2026-03-24 | Committing .xcodeproj — rejected for poor OSS contributor experience |
| Local SPM package (`Libraries/`) for core logic | Encapsulation — isolates core logic from the app target, enables fast `swift test` without Xcode | 2026-03-24 | Everything in app target — rejected for lack of modularity |
| Swift 6.2 strict concurrency (`complete`) | Eliminates data races at compile time; required for Foundation Model framework | 2026-03-24 | Relaxed concurrency — rejected, doesn't catch bugs early enough |
| SwiftUI MenuBarExtra over AppKit NSStatusItem | Native SwiftUI integration, less boilerplate, aligns with @Observable pattern | 2026-03-24 | AppKit NSStatusItem — rejected unless SwiftUI proves insufficient |
| @Observable over ObservableObject | Per-property view invalidation, less boilerplate, modern Swift pattern | 2026-03-24 | ObservableObject + @Published — legacy pattern |
| AppleScript for Notes | Only known mechanism for programmatic Notes access with folder targeting | 2026-03-24 | Scripting Bridge — rejected; NSAppleScript avoids generated bridge headers and works without App Store entitlements |
| LLM for optional summarization and title generation | Simpler toggle-based approach, graceful degradation (full transcript when LLM unavailable) | 2026-04-01 | Multi-destination classification to Reminders/Calendar/Notes — rejected as over-engineered for single-user MVP |
| Keychain for remote LLM credentials (deferred — no remote provider currently implemented) | macOS security standard — avoids plaintext secrets in config files | 2026-03-24 | Plaintext in YAML config — rejected for security |

---

## Code Conventions

**Patterns to follow:**
```swift
// Models: @Observable + @MainActor + final class
@Observable
@MainActor
final class SomeModel {
    var items: [String] = []
}
```

```swift
// Tests: Swift Testing with @Suite and @Test
@Suite("SomeModel")
struct SomeModelTests {
    @Test("descriptive test name")
    @MainActor
    func someTest() {
        // Arrange → Act → Assert using #expect
    }
}
```

```swift
// State sharing: @State at the owner, @Environment for children
@State private var appState = AppState()
// ...
.environment(appState)
```

**Patterns to avoid:**
```swift
// Do NOT use ObservableObject/@Published — use @Observable instead
class BadModel: ObservableObject {
    @Published var items: [String] = []  // ← legacy pattern
}
```

---

## Testing Strategy

**Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
**Location:** `UtterdTests/` for app-level tests, `Libraries/Tests/CoreTests/` for library tests
**Naming:** Test structs named `[Subject]Tests`, test functions describe the behavior being verified

**Test types:**
- **Unit tests (app)**: `xcodebuild -scheme Utterd -destination 'platform=macOS' test`
- **Unit tests (library)**: `cd Libraries && swift test` — fast, no Xcode required

**Testing conventions:**
- Use Swift Testing exclusively for new tests — XCTest only for legacy code that hasn't been migrated
- `@MainActor` on test functions that touch `@MainActor`-isolated types
- Arrange → Act → Assert structure; use `#expect` for assertions

---

## Git Workflow

**Branch naming:** `feat/description`, `fix/description`, `docs/description`, `chore/description`
**Commit format:** Conventional commits — `feat: `, `fix: `, `docs: `, `chore: `, `test: `
**PR process:** Build + test must pass before merge: `xcodebuild -scheme Utterd -destination 'platform=macOS' build test`

---

## Integration Points

| Service | Purpose | Auth | Docs |
|---------|---------|------|------|
| iCloud Voice Memos sync directory | Source of .m4a and .qta voice memo files | Disk access permission | `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings` |
| macOS Foundation Model (macOS 26+) | On-device LLM for optional summarization and title generation | None (on-device) | Apple platform docs |
| AppleScript (NSAppleScript) | Notes item creation with folder targeting | Automation permission | Apple AppleScript docs |
| FSEvents (CoreServices) | File system monitoring for new voice memos | Disk access permission | Apple FSEvents docs |

---

## Boundaries & Constraints

### Always Do
- Run `xcodegen generate` after modifying `project.yml` before building
- Run build + test before creating a PR
- Use Swift Testing (`@Test`, `#expect`) for all new tests
- Use `@Observable` pattern for new models — never `ObservableObject`
- Read from temporary copies of voice memo files, never the originals
- Check the dedup store before processing and update it after successful creation

### Ask First
- Before adding third-party dependencies (the project minimizes external deps for OSS simplicity)
- Before changing the pipeline stage order or adding/removing stages
- Before modifying `project.yml` target structure or build settings
- Before dropping to AppKit (NSViewRepresentable) — SwiftUI first
- Before changing the LLM provider protocol interface

### Never Do
- Never modify or delete original voice memo files in the sync directory
- Never store credentials in plaintext configuration files
- Never skip the dedup store check — processing without dedup creates duplicates
- Never process memos if the dedup store cannot be written (prevents duplicates on disk-full)
- Never send telemetry or analytics data off the machine

---

## Known Gotchas

- **Speech-to-text requires macOS 26+**: On-device transcription uses the `SpeechAnalyzer` API (available macOS 26+). Earlier macOS versions cannot run the transcription pipeline
- **Foundation Model availability for unsandboxed apps**: The app runs outside the App Store sandbox. Whether macOS Foundation Model framework works for unsandboxed apps is unconfirmed
- **Notes AppleScript limitations**: Programmatic Notes access via AppleScript is less well-documented than EventKit. Folder targeting is implemented (plain text only); rich text and HTML content formatting support need investigation
- **App is partially implemented**: The full pipeline (file detection, transcription, optional LLM summarization/title generation, and Notes creation) is wired end-to-end in `AppDelegate` on macOS 26+. The menu bar icon (`MenuBarExtra`) displays the last-processed timestamp (or "No memos processed yet"), a Settings button, and a quit button. A Settings window provides default folder selection, summarization toggle, summarization instructions input, title generation toggle, a launch-at-login toggle (via `SMAppService`), and an About section with version, log file access, and GitHub releases link
- **macOS 15 vs macOS 26 split**: On-device transcription and LLM require macOS 26+. On macOS 15–25, the pipeline does not start — new memos are not detected or processed until the user upgrades. Remote LLM fallback is a future consideration, not currently implemented
