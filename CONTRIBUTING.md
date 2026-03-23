# Contributing to Utterd

Thanks for your interest in contributing! This guide covers everything you need to get started.

## Prerequisites

- macOS 26+ for on-device transcription and LLM features
- Xcode 26+
- Swift 6.2
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Getting Started

```bash
# Clone the repo
git clone https://github.com/DaveBben/utterd.git
cd utterd

# Create Local.xcconfig with your Apple Developer Team ID (required for code signing)
echo 'DEVELOPMENT_TEAM = YOUR_TEAM_ID' > Local.xcconfig

# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -scheme Utterd -destination 'platform=macOS' build

# Run all tests
xcodebuild -scheme Utterd -destination 'platform=macOS' test

# Run library tests independently
cd Libraries && swift test
```

## Architecture

See [spec.md](spec.md) for detailed architecture decisions, code conventions, and design rationale.

Key patterns:
- SwiftUI + `@Observable` (not Combine)
- Swift 6.2 strict concurrency (`@MainActor` default isolation)
- Local Swift packages in `Libraries/` for shared modules
- Swift Testing (`@Test`, `#expect`) for new tests

## Pull Request Workflow

1. Branch from `main`
2. Make your changes
3. Ensure build and tests pass:
   ```bash
   xcodegen generate && xcodebuild -scheme Utterd -destination 'platform=macOS' build test
   ```
4. Open a PR against `main`

### PR Expectations

- Build and tests must pass
- Keep changes focused — one concern per PR
- Follow existing code patterns and conventions (see spec.md)

## Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes to user-facing behavior
- **MINOR**: New features (e.g., new summarization options, new export targets)
- **PATCH**: Bug fixes

Version numbers live in `project.yml` (lines 39-40):
- `CFBundleShortVersionString` — the SemVer display version (e.g., `1.0.0`)
- `CFBundleVersion` — integer build number, incremented per release

Git tags use the `v1.0.0` format, always matching `CFBundleShortVersionString`.

To bump the version, edit only `project.yml`, then run `xcodegen generate`.

## What Must Never Be Committed

Do not commit any of the following:

- Apple Developer Team IDs or signing identities
- API keys, tokens, or secrets of any kind
- Provisioning profiles (`.mobileprovision`, `.provisionprofile`)
- Certificates or private keys (`.p12`, `.cer`, `.pem`, `.key`)
- Environment files (`.env`)

The `.gitignore` is configured to block these patterns, but please double-check before committing.

## License

By contributing, you agree that your contributions will be licensed under the [GPL v3](LICENSE).
