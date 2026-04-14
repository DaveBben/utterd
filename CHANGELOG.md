# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- QTA file support: voice memos saved as .qta are now detected and processed alongside .m4a files, with the same 1024-byte minimum threshold and iCloud placeholder filtering
- "Voice Memos Not Set Up" alert at launch when the recordings directory is missing, with instructions to open Voice Memos and wait for iCloud sync before relaunching
- "Open Log File" button in Settings to open `utterd.log` in the default editor
- Version display and GitHub releases link in the Settings window
- DMG installer with app icon and Applications folder alias, styled via `create-dmg`
- App icon asset catalog (`Utterd/Resources/Assets.xcassets`) integrated via XcodeGen
- `scripts/compose-icon.swift`: Icon compositing script with squircle mask for transparent corners
- DMG-level notarization and stapling in the release build script
- `create-dmg` prerequisite documented in `docs/releasing.md`

### Fixed

- DMG icon label text now renders correctly in both light and dark mode (removed custom background image — Finder forces black text when a background image is set, regardless of brightness)
- Applications folder icon now displays correctly in DMG (uses Finder alias instead of symlink)
- App icon corners are now transparent (squircle clipping mask applied during compositing)

## [1.0.0] - 2026-04-08

### Added

- macOS menu bar daemon for automatic voice memo processing
- On-device transcription via SpeechAnalyzer (macOS 26+)
- On-device LLM summarization and title generation (optional, macOS 26+)
- Apple Notes integration with automatic folder targeting
- Settings window for folder selection, summarization preferences, and custom instructions
- Pipeline monitoring with real-time status in the menu bar
- Full Disk Access and Automation permission handling
