# Utterd

[![Build & Test](https://github.com/DaveBben/utterd/actions/workflows/build.yml/badge.svg)](https://github.com/DaveBben/utterd/actions/workflows/build.yml)

Utterd is a macOS menu bar app that watches your Voice Memos folder and automatically transcribes recordings into Apple Notes. With Apple Intelligence enabled, it can also summarize recordings and generate descriptive titles.

This is something I built for my own ADHD brain. I like to capture ideas by voice while driving, walking, or working, but was frustrated that there was no integration with Apple Notes.

![Application Screenshot Demo](/demo.png)

## System Requirements

- **macOS 26+ (Tahoe)** — required for on-device transcription (SpeechAnalyzer) and optional LLM summarization (Apple Intelligence)
- Apple Silicon Mac (arm64 only)

## Installation

Download the latest `.dmg` from the [Releases page](https://github.com/DaveBben/utterd/releases). The app is signed and notarized.

## Setup

1. Open the `.dmg` and drag Utterd to your Applications folder
2. Open **Voice Memos** at least once so iCloud creates the recordings directory on this Mac
3. Launch Utterd — it appears as a menu bar icon
4. Grant **Full Disk Access** when prompted (System Settings > Privacy & Security > Full Disk Access)
5. Grant **Automation** permission when prompted — needed to create notes via AppleScript
6. *(Optional)* Enable **Apple Intelligence** to unlock summarization and title generation (System Settings > Apple Intelligence & Siri)

## How It Works

1. Record a voice memo on your iPhone, iPad, or Mac
2. iCloud syncs the memo to your Mac — Utterd detects it automatically
3. Utterd transcribes the audio on-device using Apple's SpeechAnalyzer
4. (Optional) The on-device Foundation Model which ships with the latest MacOS can be used to generate a summary and descriptive titles.
5. A new note appears in your chosen Apple Notes folder

![Application Settings Window](/settings.png)

## Why Full Disk Access?

Apple doesn't expose a public API for Voice Memos. When iCloud sync is enabled, recordings are stored in `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/`. Utterd needs read access to that path — it never modifies or deletes your original recordings.

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
xcodebuild -scheme Utterd -destination 'platform=macOS' test
```

## Project Structure

```
Utterd/
  App/           Entry point, scenes, commands
  Features/      Feature modules (View + Model pairs)
  Core/          Shared services and state
  UI/            Reusable design-system components
  Resources/     Assets, privacy manifest
Libraries/       Local Swift package for shared modules
UtterdTests/     Swift Testing unit tests
```

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, coding conventions, and PR workflow.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
