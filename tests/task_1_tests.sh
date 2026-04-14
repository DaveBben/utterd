#!/usr/bin/env bash
# Task 1 — Generate gradient background image for DMG
# RED phase: asserts the NEW state that does not yet exist.
# All tests should FAIL before the implementation runs.
# set -euo pipefail is intentional. All outcome checks are wrapped in if/else
# guards so the exit-on-error behaviour is safe here. Any future additions to
# this script MUST follow the same guard pattern — bare subcommands that can
# return non-zero will abort the script before the summary prints.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_SCRIPT="$REPO_ROOT/scripts/generate-dmg-background.swift"
OUTPUT_IMAGE="$REPO_ROOT/scripts/dmg-background.png"

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
# AC1: Swift script exists at scripts/generate-dmg-background.swift
# GIVEN the task is complete,
# WHEN the scripts/ directory is inspected,
# THEN scripts/generate-dmg-background.swift exists as a regular file.
# ---------------------------------------------------------------------------

if [ -f "$SWIFT_SCRIPT" ]; then
    check "AC1: scripts/generate-dmg-background.swift exists" "pass"
else
    check "AC1: scripts/generate-dmg-background.swift exists" "fail"
fi

# ---------------------------------------------------------------------------
# AC2: Running the script produces scripts/dmg-background.png
# GIVEN the Swift script exists,
# WHEN run with 'swift scripts/generate-dmg-background.swift',
# THEN it produces scripts/dmg-background.png as a regular file.
# ---------------------------------------------------------------------------

# Remove any stale image before running so the test proves the script creates it
if [ -f "$OUTPUT_IMAGE" ]; then
    rm "$OUTPUT_IMAGE"
fi

if [ -f "$SWIFT_SCRIPT" ]; then
    # Pass explicit output path so the test definitively probes the same file
    # the script wrote — independent of the script's default-path resolution.
    if swift "$SWIFT_SCRIPT" "$OUTPUT_IMAGE" > /dev/null 2>&1; then
        if [ -f "$OUTPUT_IMAGE" ]; then
            check "AC2: running the script produces scripts/dmg-background.png" "pass"
        else
            check "AC2: running the script produces scripts/dmg-background.png" "fail"
        fi
    else
        check "AC2: running the script produces scripts/dmg-background.png" "fail"
    fi
else
    check "AC2: running the script produces scripts/dmg-background.png" "fail"
fi

# ---------------------------------------------------------------------------
# AC3: The generated PNG is exactly 1200x800 pixels
# GIVEN the generated PNG,
# WHEN inspected with sips,
# THEN sips reports pixelWidth 1200 and pixelHeight 800.
# ---------------------------------------------------------------------------

if [ -f "$OUTPUT_IMAGE" ]; then
    pixel_width="$(sips -g pixelWidth "$OUTPUT_IMAGE" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    pixel_height="$(sips -g pixelHeight "$OUTPUT_IMAGE" 2>/dev/null | awk '/pixelHeight/ {print $2}')"

    if [ "$pixel_width" = "1200" ]; then
        check "AC3a: image pixelWidth is 1200" "pass"
    else
        check "AC3a: image pixelWidth is 1200 (got: ${pixel_width:-unknown})" "fail"
    fi

    if [ "$pixel_height" = "800" ]; then
        check "AC3b: image pixelHeight is 800" "pass"
    else
        check "AC3b: image pixelHeight is 800 (got: ${pixel_height:-unknown})" "fail"
    fi
else
    check "AC3a: image pixelWidth is 1200 (no image to inspect)" "fail"
    check "AC3b: image pixelHeight is 800 (no image to inspect)" "fail"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
