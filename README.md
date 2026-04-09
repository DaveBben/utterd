# Utterd

![Application Screenshot Demo](/demo.png)

Something I built to help my ADHD brain. I use voice memos on my iPhone and Apple Watch to capture random ideas while driving, walking, working, etc. I wanted those memos to be automatically transcribed and placed into Apple Notes.

Utterd is a macOS menu bar app that watches your Voice Memos folder in the background and uses Apple's on-device SpeechAnalyzer API to transcribe recordings. Optionally, it can use Apple's on-device Foundation Model (macOS 26+) to generate a summary and descriptive title.

## How It Works

1. Record a voice memo on your iPhone, iPad, or Mac
2. iCloud syncs the memo to your Mac and Utterd detects it automatically
3. Utterd transcribes the audio on-device using SpeechAnalyzer
4. Optionally, an on-device LLM generates a summary and descriptive title
5. A new note appears in your chosen Apple Notes folder

## Key Features
![Application Settings Window](/settings.png)

- Automatically transcribes voice memos and drops them into Apple Notes
- Uses Apple's **on-device Foundation Model** for summarization and title generation
- Uses Apple's **on-device SpeechAnalyzer** for transcription
- Minimal by design — no bloat, no cloud, no manual steps


## Download

Download the latest release from the [GitHub Releases](https://github.com/DaveBben/utterd/releases) page. The `.dmg` contains a signed and notarized macOS app (arm64 only).

## Requirements
- **macOS 26+ (Tahoe)** required for on-device transcription and LLM summarization

## Setup

1. Open the `.dmg` and drag Utterd to your Applications folder
2. Open **Voice Memos** at least once so iCloud creates the recordings directory on this Mac
3. Launch Utterd, it appears as a menu bar icon
4. Grant **Full Disk Access** when prompted (System Settings > Privacy & Security > Full Disk Access) — needed to read voice memos from iCloud
5. Grant **Automation** permission when prompted — needed to create notes in Apple Notes (uses AppleScript)

## Why is Full Disk Access Needed?
Apple doesn't provide a public API for accessing voice memos. When iCloud sync is enabled, recordings are stored in `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/` on your Mac. Utterd only needs read access to that folder.


## Building from Source

### Prerequisites

- macOS 26+ (Tahoe)
- Xcode 26+
- Swift 6.2
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Build & Run

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open Utterd.xcodeproj

# Or build from the command line
xcodebuild -scheme Utterd -destination 'platform=macOS' build
```

### Testing

```bash
# Run all tests
xcodebuild -scheme Utterd -destination 'platform=macOS' test

# Run library tests independently
cd Libraries && swift test
```

Tests use Swift Testing (`@Test`, `#expect`).

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

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, coding conventions, and PR workflow.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
