# Utterd

A macOS daemon that turns voice memos into Apple Notes — automatically transcribed, optionally summarized, filed into the right folder

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 26+
- Swift 6.2
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Prerequisites

Utterd requires **Full Disk Access** to read voice memos from iCloud. On first launch, the app will prompt you to grant access in System Settings > Privacy & Security > Full Disk Access. Grant access and relaunch the app.

Utterd also requires **Automation** permission to control Apple Notes. macOS will show a one-time prompt the first time the app tries to create a note. If you deny it, go to System Settings > Privacy & Security > Automation and enable Notes for Utterd.

## Getting Started

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open Utterd.xcodeproj

# Or build from the command line
xcodebuild -scheme Utterd -destination 'platform=macOS' build
```

## Project Structure

```
Utterd/          App source code (SwiftUI + @Observable)
  App/                 Entry point, scenes, commands
  Features/            Feature modules (View + Model pairs)
  Core/                Shared services and state
  UI/                  Reusable design-system components
  Resources/           Assets, privacy manifest
Libraries/             Local Swift package for shared modules
UtterdTests/     Swift Testing unit tests
```

## Architecture

This app follows Apple's recommended SwiftUI + @Observable pattern:

- **Views** own state via `@State` and share it via `@Environment`
- **Models** are `@Observable` classes with per-property view invalidation
- **Concurrency** uses Swift 6.2 strict concurrency with `@MainActor` default isolation
- **Modularization** via local Swift packages in `Libraries/`

## Testing

```bash
# Run all tests
xcodebuild -scheme Utterd -destination 'platform=macOS' test

# Run library tests independently
cd Libraries && swift test
```

Tests use Swift Testing (`@Test`, `#expect`) for unit tests and XCUITest for UI tests.
