# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- "Voice Memos Not Set Up" alert at launch when the recordings directory is missing, with instructions to open Voice Memos and wait for iCloud sync before relaunching

## [1.0.0] - 2026-04-08

### Added

- macOS menu bar daemon for automatic voice memo processing
- On-device transcription via SpeechAnalyzer (macOS 26+)
- On-device LLM summarization and title generation (optional, macOS 26+)
- Apple Notes integration with automatic folder targeting
- Settings window for folder selection, summarization preferences, and custom instructions
- Pipeline monitoring with real-time status in the menu bar
- Full Disk Access and Automation permission handling
