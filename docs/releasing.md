# Release Process

Step-by-step guide for publishing a new Utterd release.

## Prerequisites

- Paid Apple Developer Program membership
- Notarization credentials stored in Keychain:
  ```bash
  xcrun notarytool store-credentials "Utterd-Notarize" \
    --apple-id "your@email.com" \
    --team-id "YOURTEAMID" \
    --password "app-specific-password"
  ```
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed
- [GitHub CLI](https://cli.github.com/) installed (`brew install gh`)

## Steps

### 1. Bump the version

Edit `project.yml` and update both version fields:

```yaml
CFBundleShortVersionString: "X.Y.Z"  # SemVer display version
CFBundleVersion: "N"                  # Integer build number (increment each release)
```

Then regenerate the Xcode project:

```bash
xcodegen generate
```

### 2. Update the changelog

Move items from `[Unreleased]` to a new version section in `CHANGELOG.md`:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Fixed
- ...
```

### 3. Commit and merge

```bash
git checkout -b release/vX.Y.Z
git add project.yml CHANGELOG.md
git commit -m "chore: bump version to X.Y.Z"
```

Open a PR to `main` and merge it.

### 4. Build the release

```bash
git checkout main
git pull
./scripts/build-release.sh X.Y.Z
```

The script will:
1. Verify the version matches `project.yml`
2. Archive a Release build (arm64)
3. Export with Developer ID signing
4. Notarize via `notarytool`
5. Staple the notarization ticket
6. Create a DMG at `build/Utterd-X.Y.Z.dmg`

### 5. Create the GitHub release

```bash
git tag vX.Y.Z
git push origin v X.Y.Z

gh release create vX.Y.Z \
  --title "vX.Y.Z" \
  --notes "See [CHANGELOG.md](CHANGELOG.md) for details." \
  build/Utterd-X.Y.Z.dmg
```

### 6. Verify

- [ ] Release page shows the DMG attachment
- [ ] Download the DMG and install — no Gatekeeper warnings
- [ ] App launches and appears in the menu bar
