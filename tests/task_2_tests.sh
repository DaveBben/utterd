#!/usr/bin/env bash
# Task 2 — Replace hdiutil with create-dmg and add DMG notarization
# RED phase: asserts the NEW state that does not yet exist.
# All tests should FAIL before the implementation runs.
# set -euo pipefail is intentional. Rules for adding new checks:
#   - grep/test inside `if` conditions: safe (set -e does not apply)
#   - grep result captured in a variable: MUST use `|| true` to prevent abort
#     e.g.: count=$(grep -c 'pattern' file || true)
# Any future additions that break this pattern will abort before the summary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/build-release.sh"

pass_count=0
fail_count=0

check() {
    local description="$1"
    local result="$2"   # "pass" or "fail"
    if [ "$result" = "pass" ]; then
        echo "PASS: $description"
        pass_count=$((pass_count + 1))
    else
        echo "FAIL: $description"
        fail_count=$((fail_count + 1))
    fi
}

# ---------------------------------------------------------------------------
# AC1: Valid shell syntax
# GIVEN the build script,
# WHEN bash -n scripts/build-release.sh is run,
# THEN it exits 0 (no syntax errors).
# ---------------------------------------------------------------------------

if bash -n "$SCRIPT" 2>/dev/null; then
    check "AC1: bash -n syntax check exits 0" "pass"
else
    check "AC1: bash -n syntax check exits 0" "fail"
fi

# ---------------------------------------------------------------------------
# AC2a: create-dmg invocation includes --background flag
# GIVEN the build script,
# WHEN inspected,
# THEN a create-dmg call with --background is present.
# ---------------------------------------------------------------------------

if grep -q -- '--background' "$SCRIPT"; then
    check "AC2a: create-dmg invocation includes --background flag" "pass"
else
    check "AC2a: create-dmg invocation includes --background flag" "fail"
fi

# ---------------------------------------------------------------------------
# AC2b: Applications alias is staged via Finder alias (not --app-drop-link)
# GIVEN the build script,
# WHEN inspected,
# THEN a Finder alias to /Applications is created via osascript before
# create-dmg, and --icon "Applications" positions it (NOT --app-drop-link,
# which silently fails to set the icon on newer macOS).
# ---------------------------------------------------------------------------

if grep -q 'make alias file' "$SCRIPT" && grep -q '"Applications"' "$SCRIPT"; then
    check "AC2b: Applications alias created via Finder osascript" "pass"
else
    check "AC2b: Applications alias created via Finder osascript" "fail"
fi

# ---------------------------------------------------------------------------
# AC2c: create-dmg invocation includes --icon positioning flag
# GIVEN the build script,
# WHEN inspected,
# THEN a create-dmg call with --icon (for app icon position) is present.
# ---------------------------------------------------------------------------

if grep -q -- '--icon ' "$SCRIPT"; then
    check "AC2c: create-dmg invocation includes --icon positioning flag" "pass"
else
    check "AC2c: create-dmg invocation includes --icon positioning flag" "fail"
fi

# ---------------------------------------------------------------------------
# AC2d: create-dmg invocation includes --hide-extension flag
# GIVEN the build script,
# WHEN inspected,
# THEN a create-dmg call with --hide-extension is present.
# ---------------------------------------------------------------------------

if grep -q -- '--hide-extension' "$SCRIPT"; then
    check "AC2d: create-dmg invocation includes --hide-extension flag" "pass"
else
    check "AC2d: create-dmg invocation includes --hide-extension flag" "fail"
fi

# ---------------------------------------------------------------------------
# AC3a: DMG notarization — notarytool submit appears in script
# GIVEN the build script,
# WHEN inspected,
# THEN xcrun notarytool submit appears after DMG creation (for DMG itself).
#
# The script already contains notarytool for the .app zip. We verify there
# are at least two notarytool submit calls (app + DMG), confirming a second
# submit was added for the DMG path.
# ---------------------------------------------------------------------------

submit_count=$(grep -c 'notarytool submit' "$SCRIPT" || true)
if [ "$submit_count" -ge 2 ]; then
    check "AC3a: DMG notarization (notarytool submit) present for DMG" "pass"
else
    check "AC3a: DMG notarization (notarytool submit) present for DMG" "fail"
fi

# ---------------------------------------------------------------------------
# AC3b: DMG stapling — stapler staple appears for the DMG path
# GIVEN the build script,
# WHEN inspected,
# THEN xcrun stapler staple is called on the DMG file (DMG_PATH).
#
# The script already staples the .app. We verify stapler is called with
# DMG_PATH specifically, confirming the DMG-level staple was added.
# ---------------------------------------------------------------------------

if grep -q 'stapler staple.*DMG_PATH\|stapler staple.*\.dmg' "$SCRIPT"; then
    check "AC3b: DMG stapling (stapler staple \$DMG_PATH) present" "pass"
else
    check "AC3b: DMG stapling (stapler staple \$DMG_PATH) present" "fail"
fi

# ---------------------------------------------------------------------------
# AC4: Staging step uses ditto (not cp -R)
# GIVEN the build script,
# WHEN inspected,
# THEN ditto is used to stage the app into the DMG staging directory
# (preserving extended attributes), and cp -R is NOT used for staging.
# ---------------------------------------------------------------------------

if grep -q 'ditto.*dmg-staging\|ditto.*staging' "$SCRIPT"; then
    check "AC4a: staging step uses ditto to copy app into staging dir" "pass"
else
    check "AC4a: staging step uses ditto to copy app into staging dir" "fail"
fi

if grep -q 'cp -R.*dmg-staging\|cp -R.*staging' "$SCRIPT"; then
    check "AC4b: staging step does NOT use cp -R" "fail"
else
    check "AC4b: staging step does NOT use cp -R" "pass"
fi

# ---------------------------------------------------------------------------
# AC5: Prerequisites comment lists create-dmg
# GIVEN the build script,
# WHEN inspected,
# THEN the prerequisites block mentions create-dmg.
# ---------------------------------------------------------------------------

if grep -q 'create-dmg' "$SCRIPT"; then
    check "AC5: prerequisites comment lists create-dmg" "pass"
else
    check "AC5: prerequisites comment lists create-dmg" "fail"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
