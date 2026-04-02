## Project Identity

A macOS menu bar daemon that automatically turns voice memos into Apple Notes.
It monitors the iCloud Voice Memos sync directory, transcribes audio on-device
(macOS 26+), and uses a language model to pick the right Notes folder (summarization is supported but not yet enabled) — no manual intervention after setup. Built for a single
user who wants frictionless voice capture without thinking about where things go.

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
- Never run swift test while another instance is running. Wait for background processes to complete before retrying.
- Never run `swift build` or `swift test` in background or in parallel — SwiftPM holds an exclusive lock on `.build/`.
- When running Swift tests (especially from subagents), prevent hangs from watch/interactive mode:
  - Always redirect stdin: `swift test </dev/null` — this is the primary fix. It cuts off stdin entirely, signaling unambiguously that this is a non-interactive run.
  - Pipe output as a secondary signal: `swift test </dev/null 2>&1`
  - Always wrap with a timeout: `timeout 120 swift test </dev/null`
  - Subagent prompts must explicitly instruct non-interactive flags when running tests.
- Use SwiftUI first; drop to AppKit via NSViewRepresentable only when necessary
- Never modify or delete original voice memo files — only read from temporary copies
- Build + test must pass before creating a PR: `xcodebuild -scheme Utterd -destination 'platform=macOS' build test`

## Pointers to Deeper Docs

- `spec.md` — project spec: goals, architecture decisions, code conventions, testing strategy, boundaries
- `README.md` — setup instructions and project overview
- `project.yml` — XcodeGen project definition (targets, settings, dependencies)
- `Libraries/Package.swift` — local SPM package definition
