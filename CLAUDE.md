# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

A macOS daemon that routes voice memos to Reminders, Calendar, and Notes

A macOS app built with SwiftUI, @Observable, and Swift 6.2 concurrency.
Minimum deployment target: macOS 15 (Sequoia).

## Development Commands

```bash
# Build the app
xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build

# Run tests (Swift Testing + XCTest)
xcodebuild -scheme Utterd -destination 'platform=macOS' test

# Build local SPM libraries only
cd Libraries && swift build && swift test

# Lint (if SwiftLint is installed)
swiftlint lint --strict

# Format (if swift-format is installed)
swift-format format -i -r Utterd/ UtterdTests/ Libraries/
```

## Architecture

- **Pattern**: SwiftUI + @Observable (Apple's native "MV" pattern)
- **State**: @Observable classes owned via @State, shared via @Environment
- **Concurrency**: Swift 6.2 strict concurrency with @MainActor default isolation
- **Modularization**: Local Swift package in Libraries/ with feature targets
- **Dependencies flow**: Features -> Core (unidirectional)

### Directory Layout

```
Utterd/
  App/           - @main entry, scenes, app-level config, commands
  Features/      - One folder per feature/screen (View + Model pairs)
  Core/          - Shared services, networking, persistence
  UI/            - Design system, reusable SwiftUI components
  AppKitBridges/ - NSViewRepresentable wrappers (only when needed)
  Resources/     - Assets, PrivacyInfo.xcprivacy, Info.plist
```

## Key Conventions

- Use @Observable, NOT ObservableObject/@Published/@StateObject
- Use Swift Testing (@Test, #expect) for new tests, NOT XCTest assertions
- Use async/await and actors, NOT GCD (DispatchQueue/DispatchGroup)
- Use AsyncSequence (Swift Async Algorithms), NOT Combine for new reactive code
- Use SwiftUI first, drop to AppKit via NSViewRepresentable only when necessary
- Privacy manifest (PrivacyInfo.xcprivacy) must be kept current

## Project References

- `spec.md` — product requirements, user stories, and acceptance criteria

## Before Creating PR

Build + test must pass:
```bash
xcodebuild -scheme Utterd -destination 'platform=macOS' build test
```
