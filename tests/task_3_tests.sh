#!/usr/bin/env bash
# Task 3 — Add create-dmg to release prerequisites documentation
# RED phase: asserts the NEW state that does not yet exist.
# All tests should FAIL before the implementation runs.
# set -euo pipefail is intentional. All outcome checks are wrapped in if/else
# guards so the exit-on-error behaviour is safe here. Any future additions to
# this script MUST follow the same guard pattern — bare subcommands that can
# return non-zero will abort the script before the summary prints.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS="$REPO_ROOT/docs/releasing.md"

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
# AC1: create-dmg is mentioned in the prerequisites section
# GIVEN docs/releasing.md,
# WHEN inspected,
# THEN the prerequisites section lists create-dmg by name.
# ---------------------------------------------------------------------------

if grep -q 'create-dmg' "$DOCS"; then
    check "AC1: prerequisites section mentions create-dmg" "pass"
else
    check "AC1: prerequisites section mentions create-dmg" "fail"
fi

# ---------------------------------------------------------------------------
# AC2: A GitHub link to github.com/create-dmg is present
# GIVEN the prerequisites section,
# WHEN inspected,
# THEN there is a link to github.com/create-dmg (the project's GitHub org/repo).
# ---------------------------------------------------------------------------

if grep -q 'github\.com/create-dmg' "$DOCS"; then
    check "AC2: GitHub link github.com/create-dmg present" "pass"
else
    check "AC2: GitHub link github.com/create-dmg present" "fail"
fi

# ---------------------------------------------------------------------------
# AC3: A brew install command for create-dmg is present
# GIVEN the prerequisites section,
# WHEN inspected,
# THEN there is a brew install create-dmg command.
# ---------------------------------------------------------------------------

if grep -q 'brew install create-dmg' "$DOCS"; then
    check "AC3: brew install create-dmg command present" "pass"
else
    check "AC3: brew install create-dmg command present" "fail"
fi

# ---------------------------------------------------------------------------
# AC4: Format matches the XcodeGen entry — markdown link + inline code install
# GIVEN the prerequisite entry for create-dmg,
# WHEN compared to the XcodeGen entry format,
# THEN it uses a markdown link `[create-dmg](URL)` with a backtick-fenced
# install command on the same line (e.g. `brew install create-dmg`).
#
# The XcodeGen line reads: - [XcodeGen](...) installed
# The GitHub CLI line reads: - [GitHub CLI](...) installed (`brew install gh`)
# The expected create-dmg line: - [create-dmg](...): `brew install create-dmg`
# We verify the markdown link syntax and the inline code block are present
# on the same bullet line.
# ---------------------------------------------------------------------------

if grep -q '\[create-dmg\](https://github\.com/create-dmg' "$DOCS"; then
    check "AC4a: markdown link [create-dmg](https://github.com/create-dmg/...) present" "pass"
else
    check "AC4a: markdown link [create-dmg](https://github.com/create-dmg/...) present" "fail"
fi

if grep -q '\[create-dmg\].*\`brew install create-dmg\`' "$DOCS"; then
    check "AC4b: inline code \`brew install create-dmg\` appears on the same line as the markdown link" "pass"
else
    check "AC4b: inline code \`brew install create-dmg\` appears on the same line as the markdown link" "fail"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
