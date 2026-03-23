#!/bin/bash
set -euo pipefail

# Build a signed, notarized DMG for release.
#
# Prerequisites:
#   - Xcode 26+ with Developer ID signing configured
#   - XcodeGen installed (brew install xcodegen)
#   - Notarization credentials stored in Keychain:
#     xcrun notarytool store-credentials "Utterd-Notarize" \
#       --apple-id "your@email.com" \
#       --team-id "YOURTEAMID" \
#       --password "app-specific-password"
#
# Usage:
#   ./scripts/build-release.sh 1.0.0

# Read DEVELOPMENT_TEAM from Local.xcconfig
XCCONFIG="$(cd "$(dirname "$0")/.." && pwd)/Local.xcconfig"
if [[ ! -f "$XCCONFIG" ]]; then
  echo "Error: Local.xcconfig not found. Create it with:"
  echo "  echo 'DEVELOPMENT_TEAM = YOUR_TEAM_ID' > Local.xcconfig"
  exit 1
fi
DEVELOPMENT_TEAM=$(grep 'DEVELOPMENT_TEAM' "$XCCONFIG" | sed 's/.*= *//')
if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "Error: DEVELOPMENT_TEAM not set in Local.xcconfig"
  exit 1
fi

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
fi

# Validate version format (SemVer)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Version must be in SemVer format (e.g., 1.0.0)"
  exit 1
fi

# Verify version in project.yml matches
PROJECT_VERSION=$(grep 'CFBundleShortVersionString' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
if [[ "$PROJECT_VERSION" != "$VERSION" ]]; then
  echo "Error: Version mismatch"
  echo "  project.yml: $PROJECT_VERSION"
  echo "  Argument:    $VERSION"
  echo ""
  echo "Update project.yml first, then run xcodegen generate."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Utterd.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Utterd-${VERSION}.dmg"

echo "==> Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Generating Xcode project"
cd "$PROJECT_DIR"
xcodegen generate

echo "==> Archiving (Release, arm64)"
xcodebuild archive \
  -scheme Utterd \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  | tail -5

echo "==> Exporting archive"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_PATH" \
  | tail -5

APP_PATH="$EXPORT_PATH/Utterd.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: Exported app not found at $APP_PATH"
  exit 1
fi

echo "==> Zipping app for notarization"
APP_ZIP="$BUILD_DIR/Utterd.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

echo "==> Notarizing"
xcrun notarytool submit "$APP_ZIP" \
  --keychain-profile "Utterd-Notarize" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

echo "==> Creating DMG"
hdiutil create \
  -volname "Utterd" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -f "$APP_ZIP"

echo ""
echo "==> Done!"
echo "DMG: $DMG_PATH"
echo "SHA-256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v${VERSION} --title \"v${VERSION}\" --notes-file CHANGELOG_EXCERPT.md \"${DMG_PATH}\""
