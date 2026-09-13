#!/usr/bin/env bash
# scripts/test-install.sh — regression tests for install.sh's guarded-block
# refresh (--force) and drift check (--check). Runs against a scratch HOME,
# never the caller's real ~/.claude. Exits 1 on any failed assertion.
#
# Usage: bash scripts/test-install.sh

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$LIB/install.sh"
FAIL=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL=1; }

assert_eq() { # $1 = actual, $2 = expected, $3 = description
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

assert_marker_count() { # $1 = file, $2 = expected count, $3 = description
  local n
  n="$(grep -c "<!-- ways-of-working:" "$1" 2>/dev/null || true)"
  assert_eq "$n" "$2" "$3"
}

marker_line() { echo "<!-- ways-of-working:$1 -->"; }

# --- Test 1-4: --claude-user, fresh install, drift, force refresh, clean check ---

HOME1="$(mktemp -d)"
export HOME="$HOME1"

"$INSTALL" --claude-user --profile frontier >/dev/null

CLAUDE_MD="$HOME1/.claude/CLAUDE.md"
[ -f "$CLAUDE_MD" ] && pass "fresh install: CLAUDE.md created" || fail "fresh install: CLAUDE.md created"
assert_marker_count "$CLAUDE_MD" 1 "fresh install: exactly one marker"
grep -qF "$(marker_line frontier)" "$CLAUDE_MD" && pass "fresh install: frontier marker present" \
  || fail "fresh install: frontier marker present"

# Edit one line inside the installed guarded block.
sed -i 's/^\*\*Honesty\.\*\*.*/**Honesty.** EDITED FOR TEST./' "$CLAUDE_MD"
grep -q "EDITED FOR TEST" "$CLAUDE_MD" && pass "drift setup: edited installed block" \
  || fail "drift setup: edited installed block"

if "$INSTALL" --check --profile frontier >/tmp/check-drift.out 2>&1; then
  fail "--check reports drift after edit (exited 0, expected 1)"
else
  pass "--check exits non-zero after edit"
fi
grep -q "DRIFT: CLAUDE.md block (frontier)" /tmp/check-drift.out \
  && pass "--check reports DRIFT: CLAUDE.md block (frontier)" \
  || fail "--check reports DRIFT: CLAUDE.md block (frontier)"

"$INSTALL" --claude-user --profile frontier --force >/dev/null
assert_marker_count "$CLAUDE_MD" 1 "--force: exactly one marker after refresh"
expected_block="$(printf '%s\n' "$(marker_line frontier)"; cat "$LIB/claude-md/global-frontier.md")"
actual_block="$(awk -v marker="$(marker_line frontier)" '
  $0 == marker { print; skip = 1; next }
  skip && index($0, "<!-- ways-of-working:") == 1 { exit }
  skip { print }
' "$CLAUDE_MD")"
assert_eq "$actual_block" "$expected_block" "--force: block content equals claude-md/global-frontier.md"

if "$INSTALL" --check --profile frontier >/tmp/check-clean.out 2>&1; then
  pass "--check is clean after --force"
else
  fail "--check is clean after --force"
  cat /tmp/check-clean.out
fi

# --- Test 5: profile switch with --force leaves exactly one marker ---

"$INSTALL" --claude-user --profile local --force >/dev/null
assert_marker_count "$CLAUDE_MD" 1 "profile switch --force: exactly one marker"
grep -qF "$(marker_line local)" "$CLAUDE_MD" && pass "profile switch --force: local marker present" \
  || fail "profile switch --force: local marker present"
grep -qF "$(marker_line frontier)" "$CLAUDE_MD" && fail "profile switch --force: frontier marker removed" \
  || pass "profile switch --force: frontier marker removed"

rm -rf "$HOME1"

# --- Test 6: the guarded-block mechanism is generic, not hardcoded to
# $HOME/.claude/CLAUDE.md — exercise the same helper functions directly
# against a project-shaped scratch CLAUDE.md (as --claude-project would use).

PROJ="$(mktemp -d)"
PROJ_CLAUDE_MD="$PROJ/.claude/CLAUDE.md"
mkdir -p "$PROJ/.claude"

# shellcheck disable=SC1090
source "$INSTALL"
DRY_RUN=0
FORCE=0

marker="$(marker_line frontier)"
mkdir -p "$(dirname "$PROJ_CLAUDE_MD")"
{ echo ""; echo "$marker"; cat "$LIB/claude-md/global-frontier.md"; } >> "$PROJ_CLAUDE_MD"
assert_marker_count "$PROJ_CLAUDE_MD" 1 "project CLAUDE.md: fresh install has one marker"

sed -i 's/^\*\*Honesty\.\*\*.*/**Honesty.** EDITED FOR TEST./' "$PROJ_CLAUDE_MD"
before="$(extract_guarded_block "$PROJ_CLAUDE_MD" "$marker")"
expected="$(printf '%s\n' "$marker"; cat "$LIB/claude-md/global-frontier.md")"
[ "$before" != "$expected" ] && pass "project CLAUDE.md: edited block differs from source" \
  || fail "project CLAUDE.md: edited block differs from source"

guarded_block_replace "$PROJ_CLAUDE_MD" "$marker" "$LIB/claude-md/global-frontier.md"
assert_marker_count "$PROJ_CLAUDE_MD" 1 "project CLAUDE.md: exactly one marker after refresh"
after="$(extract_guarded_block "$PROJ_CLAUDE_MD" "$marker")"
assert_eq "$after" "$expected" "project CLAUDE.md: block content equals source after refresh"

rm -rf "$PROJ"

if [ "$FAIL" -eq 1 ]; then
  echo "test-install.sh: FAILED"
  exit 1
fi
echo "test-install.sh: all assertions passed"
