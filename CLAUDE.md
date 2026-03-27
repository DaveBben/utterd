## Project Identity

A macOS menu bar daemon that automatically triages voice memos into Reminders, Calendar, and Notes.
It monitors the iCloud Voice Memos sync directory, extracts embedded transcripts, classifies them
via a language model (on-device or remote), and creates items in the destination apps — no manual
intervention after setup. Built for a single productivity-minded user who wants voice capture as a
reliable front door to their trusted systems.

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

- Use SwiftUI first; drop to AppKit via NSViewRepresentable only when necessary
- Never modify or delete original voice memo files — only read from temporary copies
- Build + test must pass before creating a PR: `xcodebuild -scheme Utterd -destination 'platform=macOS' build test`

## Pointers to Deeper Docs

- `spec.md` — product requirements, user stories, acceptance criteria, and pipeline stages
- `docs/architecture.md` — system architecture, quality goals, tech stack rationale, and constraints
- `README.md` — setup instructions and project overview
- `project.yml` — XcodeGen project definition (targets, settings, dependencies)
- `Libraries/Package.swift` — local SPM package definition
