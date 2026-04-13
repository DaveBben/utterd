#!/usr/bin/env bash
# Task 0 — Set up Xcode asset catalog with app icon
# RED phase: asserts the NEW state that does not yet exist.
# All tests should FAIL before the implementation runs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_SET="$REPO_ROOT/Utterd/Resources/Assets.xcassets/AppIcon.appiconset"
CATALOG_ROOT_JSON="$REPO_ROOT/Utterd/Resources/Assets.xcassets/Contents.json"
APPICONS_DIR="$REPO_ROOT/AppIcons"

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
# AC1: Asset catalog root Contents.json exists
# GIVEN the asset catalog exists at Utterd/Resources/Assets.xcassets/,
# WHEN xcodegen generate is run,
# THEN the Xcode project includes the AppIcon asset set.
# (Structural pre-condition: catalog root must be present for xcodegen to pick it up.)
# ---------------------------------------------------------------------------

if [ -f "$CATALOG_ROOT_JSON" ]; then
    check "AC1a: Utterd/Resources/Assets.xcassets/Contents.json exists" "pass"
else
    check "AC1a: Utterd/Resources/Assets.xcassets/Contents.json exists" "fail"
fi

if [ -d "$ASSET_SET" ]; then
    check "AC1b: AppIcon.appiconset/ directory exists inside asset catalog" "pass"
else
    check "AC1b: AppIcon.appiconset/ directory exists inside asset catalog" "fail"
fi

if [ -f "$ASSET_SET/Contents.json" ]; then
    check "AC1c: AppIcon.appiconset/Contents.json manifest exists" "pass"
else
    check "AC1c: AppIcon.appiconset/Contents.json manifest exists" "fail"
fi

# ---------------------------------------------------------------------------
# AC2: App bundle icon resources — icon PNGs present in asset set
# GIVEN the project is built,
# WHEN the app bundle is inspected,
# THEN it contains the app icon resources.
# (Structural pre-condition: all icon sizes must be in the asset set.)
# ---------------------------------------------------------------------------

for size in 16 32 64 128 256 512 1024; do
    if [ -f "$ASSET_SET/${size}.png" ]; then
        check "AC2: ${size}.png present in AppIcon.appiconset/" "pass"
    else
        check "AC2: ${size}.png present in AppIcon.appiconset/" "fail"
    fi
done

# ---------------------------------------------------------------------------
# AC3: AppIcons/ folder removed
# GIVEN the AppIcons/ folder existed,
# WHEN this task completes,
# THEN AppIcons/ no longer exists.
# ---------------------------------------------------------------------------

if [ ! -d "$APPICONS_DIR" ]; then
    check "AC3: AppIcons/ directory no longer exists" "pass"
else
    check "AC3: AppIcons/ directory no longer exists" "fail"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
