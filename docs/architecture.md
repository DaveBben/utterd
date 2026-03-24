# Utterd Architecture
**Date**: 2026-03-24
**Status**: Draft
**Author**: Dave
**Spec**: [spec.md](../spec.md)

---

## 1. Introduction & Goals

Utterd is a macOS menu bar daemon that automatically triages voice memos into Reminders, Calendar, and Notes. The architecture optimizes for **reliability** (every memo is processed exactly once), **privacy** (on-device processing by default), and **maintainability** (a sequential pipeline with isolated, testable stages). See [spec.md](../spec.md) for the full problem statement.

### Quality Goals

| Priority | Quality Goal | Scenario |
|----------|-------------|----------|
| 1 | Reliability | A memo recorded on a phone arrives on disk; within 5 minutes it appears as the correct item in the destination app — across 20 consecutive memos with zero misses or duplicates, even through app restarts |
| 2 | Privacy | When using the on-device language model, no memo content leaves the machine. The user is explicitly informed when transcript text will be sent to a remote endpoint |
| 3 | Maintainability | Each pipeline stage (detection, extraction, classification, routing, creation) can be developed, tested, and replaced independently without modifying other stages |
| 4 | Operability | Every processing failure is logged with memo identity, failure stage, and reason — visible in the menu bar within 10 seconds and persisted across restarts |

---

## 2. Context & Scope

Utterd sits between the macOS file system (where voice memos sync via iCloud) and three destination apps. It uses a language model to classify and extract structured data, then creates items via system APIs.

### System Boundary Diagram

```
┌─────────────────┐       ┌─────────────────────────────┐       ┌─────────────────┐
│   iCloud Sync   │──────▶│                             │──────▶│   Reminders     │
│  (Voice Memos)  │ files │                             │EventKit│  (EventKit)    │
└─────────────────┘       │                             │       └─────────────────┘
                          │                             │
                          │         Utterd              │       ┌─────────────────┐
                          │      (menu bar daemon)      │──────▶│   Calendar      │
                          │                             │EventKit│  (EventKit)    │
┌─────────────────┐       │                             │       └─────────────────┘
│  macOS Foundation│◀─────│                             │
│  Model (on-device│ prompts│                           │       ┌─────────────────┐
│  LLM, macOS 26+)│──────▶│                             │──────▶│   Notes         │
└─────────────────┘results│                             │Script- │  (Scripting     │
                          │                             │ ing    │   Bridge)       │
┌─────────────────┐       │                             │Bridge  └─────────────────┘
│  Remote LLM     │◀─────│                             │
│  (OpenAI-compat)│──────▶│                             │
└─────────────────┘ HTTPS └─────────────────────────────┘
                                     │         ▲
                          ┌──────────▼─────────┤
                          │  Local File System │
                          │  (dedup store,     │
                          │   failure log,     │
                          │   YAML config)     │
                          └────────────────────┘
```

### External Interfaces

| External Actor / System | Interface | Data Exchanged | Direction | Protocol |
|------------------------|-----------|---------------|-----------|----------|
| iCloud Sync (Voice Memos) | Watched directory | .m4a audio files with embedded transcripts | In | FSEvents file monitoring |
| macOS Foundation Model | On-device LLM | Transcript text → classification + structured data | Both | Framework API (macOS 26+) |
| Remote LLM endpoint | OpenAI-compatible API | Transcript text → classification + structured data | Both | HTTPS (REST) |
| Reminders | EventKit API | Reminder items (title, due date, list) | Out | EventKit framework |
| Calendar | EventKit API | Calendar events (title, start, duration, calendar) | Out | EventKit framework |
| Notes | Scripting Bridge | Notes (title, body, folder) | Out | Scripting Bridge |
| System Keychain | Security framework | Remote endpoint credentials | In | Keychain Services API |
| Local File System | File I/O | Dedup store, failure log, YAML config, temp copies | Both | Foundation file APIs |

---

## 3. Solution Strategy

- **Sequential pipes-and-filters pipeline** — each memo flows through detection → copy → extraction → classification → data extraction → routing → creation → dedup recording → cleanup. Stages are isolated functions with typed inputs/outputs, making them independently testable. This serves **reliability** (a failure at any stage halts that memo cleanly) and **maintainability** (stages can be swapped).

- **Protocol-based LLM provider abstraction** — a Swift protocol defines the language model interface; concrete types implement on-device (Foundation Model) and remote (OpenAI-compatible). This serves **privacy** (on-device is default) and **maintainability** (new providers without pipeline changes).

- **Exactly-once processing via persistent dedup store** — a file-identity-based store checked before processing and written after successful creation. This serves **reliability** (no duplicates, even across restarts).


---

## 4. Tech Stack

| Technology | Version | Purpose | Rationale |
|-----------|---------|---------|-----------|
| Swift | 6.2 | Primary language | Required for macOS Foundation Model framework; strict concurrency eliminates data races at compile time |
| SwiftUI | macOS 15+ | Menu bar UI | Native macOS menu bar integration (MenuBarExtra); @Observable eliminates boilerplate vs AppKit |
| XcodeGen | latest | Project generation | Avoids Xcode project merge conflicts; project.yml is human-readable and diffable |
| Swift Package Manager | built-in | Local library modularization | `Libraries/` package enables fast isolated builds and tests of core logic without Xcode |
| EventKit | macOS 15+ | Reminders & Calendar item creation | Only supported API for programmatic Reminders/Calendar access on macOS |
| FSEvents (Foundation) | macOS 15+ | File system monitoring | OS-level file watching — low overhead, immediate notification of new files |
| macOS Foundation Model | macOS 26+ | On-device LLM for classification/extraction | Privacy-first — no network calls; zero-config for users on macOS 26+ |
| Scripting Bridge | macOS 15+ | Notes item creation | Only known mechanism for programmatic Notes access with folder targeting |
| Keychain Services | macOS 15+ | Remote LLM credential storage | System keychain is the secure standard for credential storage on macOS; avoids plaintext config |
| Swift Testing | Xcode 26+ | Unit and integration tests | Modern test framework with @Test, #expect; better diagnostics than XCTest |
| YAML (via Codable or swift-yaml) | TBD | Routing rules configuration | Human-readable, widely understood format for configuration; spec requirement |

---

## 5. Constraints

### Technical Constraints

- The app must never modify or delete original voice memo files in the sync directory — only read from temporary copies (AC-04.3, AC-04.4)
- The app must never process a memo without first checking and later updating the dedup store — skipping either direction creates duplicates or missed memos (AC-08.1-08.4)
- Credentials for remote endpoints must never be stored in plaintext configuration files — Keychain Services only (NFR: Security)
- The app must not process additional memos if the dedup store cannot be written (disk full scenario) — prevents duplicates (Edge Case in spec)

### Organizational Constraints

- Single developer — architecture must minimize operational complexity and favor well-documented Apple platform APIs over third-party dependencies
- No App Store distribution planned — app runs unsandboxed with broad disk access, which simplifies file system monitoring but means Foundation Model framework availability must be verified (spec open question)

### Regulatory / Compliance Constraints

- No remote telemetry or analytics — all data stays local (spec: explicitly out of scope)
- When remote LLM is used, user must be informed that transcript text will be sent to the configured server (AC-09.5)

