## Project Identity

A macOS menu bar daemon that automatically turns voice memos into Apple Notes.
It monitors the iCloud Voice Memos sync directory, transcribes audio on-device
(macOS 26+), and optionally uses an on-device language model to summarize transcripts and generate descriptive titles. Built for a single user who wants frictionless voice capture without thinking about where things go.

## Tech Stack and Codebase Map

- Language: Swift 6.2 (strict concurrency — `SWIFT_STRICT_CONCURRENCY: complete`)
- UI: SwiftUI (macOS 15+) with @Observable pattern
- Project generation: XcodeGen (`project.yml` → `Utterd.xcodeproj`)
- Package manager: Swift Package Manager (local package in `Libraries/`)
- Testing: Swift Testing (@Test, #expect) — XCTest only for legacy
- Min deployment: macOS 15.0 (Sequoia); on-device LLM requires macOS 26+

### Directory Layout

- `Utterd/App/` — @main entry point, scenes, commands, settings
- `Utterd/Features/` — Feature modules (View + Model pairs)
- `Utterd/Core/` — Shared services, networking, persistence, app state
- `Utterd/UI/` — Design system, reusable SwiftUI components
- `Utterd/AppKitBridges/` — NSViewRepresentable wrappers (only when needed)
- `Utterd/Resources/` — Assets, Info.plist, PrivacyInfo.xcprivacy
- `Libraries/` — Local SPM package (`Core` target + `CoreTests`)
- `UtterdTests/` — App-level unit tests

## Operational Commands

- `xcodegen generate` — regenerate Xcode project from `project.yml`
- `xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build` — full build
- `xcodebuild -scheme Utterd -destination 'platform=macOS' test` — run all tests
- `cd Libraries && swift build && swift test` — build and test local SPM package only
- `swiftlint lint --strict` — lint (requires SwiftLint installed)
- `swift-format format -i -r Utterd/ UtterdTests/ Libraries/` — format (requires swift-format installed)

## Critical Constraints
- Never run `swift build` or `swift test` in background or in parallel — SwiftPM holds an exclusive lock on `.build/`. Wait for any running instance to finish before retrying.
- When running Swift tests, prevent hangs from watch/interactive mode:
  - Redirect stdin: `swift test </dev/null` (primary fix — signals non-interactive run)
  - Wrap with a timeout: `timeout 120 swift test </dev/null 2>&1`
  - Subagent prompts must explicitly pass these flags.
- Use SwiftUI first; drop to AppKit via `NSViewRepresentable` only when necessary.
- Never modify or delete original voice memo files — only read from temporary copies.
- Build + test must pass before creating a PR: `xcodebuild -scheme Utterd -destination 'platform=macOS' build test`.
- Update `CHANGELOG.md` on behavior-visible changes.
- After significant implementation changes, update `spec.md`'s Current State section. Stale specs are worse than no specs.

## Pointers to Deeper Docs

- `spec.md` — current state, architecture overview, external dependencies, boundaries, gotchas
- `README.md` — setup and project overview
- `CHANGELOG.md` — released and unreleased changes
- `docs/releasing.md` — release checklist for signed + notarized DMG
- `project.yml` — XcodeGen project definition (targets, settings, dependencies)
- `Libraries/Package.swift` — local SPM package definition
