#!/usr/bin/env bash
# scripts/test-install.sh — regression tests for install.sh's guarded-block
# refresh (--force) and drift check (--check). Drives everything through the
# real CLI against scratch HOMEs under a single tmp root; never touches the
# caller's real ~/.claude. Exits 1 on any failed assertion.
#
# Usage: bash scripts/test-install.sh

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$LIB/install.sh"

bash -n "$INSTALL"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

FAIL=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL=1; }

assert_eq() { # $1 = actual, $2 = expected, $3 = description
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

assert_marker_count() { # $1 = file, $2 = expected count, $3 = description
  local n
  n="$(grep -c "ways-of-working:" "$1" 2>/dev/null || true)"
  assert_eq "$n" "$2" "$3"
}

assert_true() { # $1 = description, $2.. = condition command; passes if it exits 0
  local desc="$1"
  shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}

assert_false() { # $1 = description, $2.. = condition command; passes if it exits non-zero
  local desc="$1"
  shift
  if "$@"; then fail "$desc"; else pass "$desc"; fi
}

marker_line() { echo "<!-- ways-of-working:$1 -->"; }
end_marker_line() { echo "<!-- /ways-of-working:$1 -->"; }

# --- 1-4: --claude-user, fresh install, drift, force refresh, clean check ---

HOME1="$TMPROOT/home1"
mkdir -p "$HOME1"
export HOME="$HOME1"

"$INSTALL" --claude-user --profile frontier >/dev/null

CLAUDE_MD="$HOME1/.claude/CLAUDE.md"
assert_true "fresh install: CLAUDE.md created" [ -f "$CLAUDE_MD" ]
assert_marker_count "$CLAUDE_MD" 2 "fresh install: begin + end marker (2 lines)"
assert_true "fresh install: frontier begin marker present" grep -qxF "$(marker_line frontier)" "$CLAUDE_MD"
assert_true "fresh install: frontier end marker present" grep -qxF "$(end_marker_line frontier)" "$CLAUDE_MD"

# Edit one line inside the installed guarded block.
sed -i 's/^\*\*Honesty\.\*\*.*/**Honesty.** EDITED FOR TEST./' "$CLAUDE_MD"
assert_true "drift setup: edited installed block" grep -q "EDITED FOR TEST" "$CLAUDE_MD"

if "$INSTALL" --check --profile frontier >"$TMPROOT/check-drift.out" 2>&1; then
  fail "--check reports drift after edit (exited 0, expected 1)"
else
  pass "--check exits non-zero after edit"
fi
assert_true "--check reports DRIFT: CLAUDE.md block (frontier)" \
  grep -q "DRIFT: CLAUDE.md block (frontier)" "$TMPROOT/check-drift.out"

"$INSTALL" --claude-user --profile frontier --force >/dev/null
assert_marker_count "$CLAUDE_MD" 2 "--force: exactly one begin + one end marker after refresh"
actual_block="$(sed -n '/^<!-- ways-of-working:frontier -->$/,/^<!-- \/ways-of-working:frontier -->$/p' "$CLAUDE_MD")"
expected_block="$(printf '%s\n' "$(marker_line frontier)"; cat "$LIB/claude-md/global-frontier.md"; printf '%s\n' "$(end_marker_line frontier)")"
assert_eq "$actual_block" "$expected_block" "--force: block content equals claude-md/global-frontier.md, bounded by markers"

if "$INSTALL" --check --profile frontier >"$TMPROOT/check-clean.out" 2>&1; then
  pass "--check is clean after --force"
else
  fail "--check is clean after --force"
  cat "$TMPROOT/check-clean.out"
fi

# --- 5: trailing user content after the block survives --force and is not drift ---

{
  echo ""
  echo "## My personal notes"
  echo "Remember to buy milk."
} >> "$CLAUDE_MD"
"$INSTALL" --claude-user --profile frontier --force >/dev/null
assert_true "trailing user content survives --force" grep -q "Remember to buy milk." "$CLAUDE_MD"
if "$INSTALL" --check --profile frontier >"$TMPROOT/check-trailing.out" 2>&1; then
  pass "trailing user content is not reported as drift"
else
  fail "trailing user content is not reported as drift"
  cat "$TMPROOT/check-trailing.out"
fi

# --- 6: profile switch with --force leaves exactly one marker pair (the other profile's) ---

"$INSTALL" --claude-user --profile local --force >/dev/null
assert_marker_count "$CLAUDE_MD" 2 "profile switch --force: exactly one begin + one end marker"
assert_true "profile switch --force: local marker present" grep -qxF "$(marker_line local)" "$CLAUDE_MD"
assert_false "profile switch --force: frontier marker removed" grep -qxF "$(marker_line frontier)" "$CLAUDE_MD"
assert_true "profile switch --force: trailing user content still survives" grep -q "Remember to buy milk." "$CLAUDE_MD"

rm -rf "$HOME1"

# --- 7: CRLF file — the range/marker logic tolerates \r line endings ---

HOME2="$TMPROOT/home2"
mkdir -p "$HOME2"
export HOME="$HOME2"
"$INSTALL" --claude-user --profile frontier >/dev/null
CLAUDE_MD2="$HOME2/.claude/CLAUDE.md"
sed -i 's/$/\r/' "$CLAUDE_MD2"
"$INSTALL" --claude-user --profile frontier --force >/dev/null
assert_marker_count "$CLAUDE_MD2" 2 "CRLF file: --force finds the real end marker, no duplication"
assert_false "CRLF file: no legacy backup created (a real end marker was present)" [ -f "${CLAUDE_MD2}.bak" ]

rm -rf "$HOME2"

# --- 8: legacy block (begin marker, no end marker) refreshes, backs up, and warns ---

HOME3="$TMPROOT/home3"
mkdir -p "$HOME3/.claude"
export HOME="$HOME3"
CLAUDE_MD3="$HOME3/.claude/CLAUDE.md"
{
  echo ""
  marker_line frontier
  echo "STALE CONTENT FROM BEFORE THIS FIX"
  echo ""
  echo "My personal note that was appended after the old block."
} > "$CLAUDE_MD3"

legacy_out="$("$INSTALL" --claude-user --profile frontier --force 2>&1 >/dev/null)"
if echo "$legacy_out" | grep -q "legacy guarded block"; then
  pass "legacy block: warning printed"
else
  fail "legacy block: warning printed"
fi
echo "--- legacy backup warning line ---"
echo "$legacy_out" | grep "legacy guarded block" || true

assert_true "legacy block: .bak created" [ -f "${CLAUDE_MD3}.bak" ]
assert_true "legacy block: personal note preserved in .bak" \
  grep -q "My personal note that was appended after the old block." "${CLAUDE_MD3}.bak"
assert_false "legacy block: personal note removed from the live file (expected — it must be re-added by hand)" \
  grep -q "My personal note that was appended after the old block." "$CLAUDE_MD3"
assert_marker_count "$CLAUDE_MD3" 2 "legacy block: exactly one begin + one end marker after refresh"
if "$INSTALL" --check --profile frontier >"$TMPROOT/check-legacy.out" 2>&1; then
  pass "legacy block: --check is clean after the one-time --force refresh"
else
  fail "legacy block: --check is clean after the one-time --force refresh"
  cat "$TMPROOT/check-legacy.out"
fi

rm -rf "$HOME3"

# --- 9: --check reports LEGACY (not DRIFT) for a block with no end marker ---

HOME4="$TMPROOT/home4"
mkdir -p "$HOME4/.claude"
export HOME="$HOME4"
CLAUDE_MD4="$HOME4/.claude/CLAUDE.md"
{ echo ""; marker_line frontier; cat "$LIB/claude-md/global-frontier.md"; } > "$CLAUDE_MD4"
if "$INSTALL" --check --profile frontier >"$TMPROOT/check-legacy-report.out" 2>&1; then
  fail "--check exits non-zero-ish is not required, but LEGACY must be reported"
fi
assert_true "--check reports LEGACY for a block with no end marker" \
  grep -q "LEGACY: CLAUDE.md block (frontier) has no end marker; run --force once" "$TMPROOT/check-legacy-report.out"
assert_false "--check does not report DRIFT for a legacy block (LEGACY only)" \
  grep -q "^DRIFT: CLAUDE.md block" "$TMPROOT/check-legacy-report.out"

rm -rf "$HOME4"

# --- 10: legacy-name marker (pre-#13 prefix) migrates and refreshes in one run ---

HOME5="$TMPROOT/home5"
mkdir -p "$HOME5/.claude"
export HOME="$HOME5"
CLAUDE_MD5="$HOME5/.claude/CLAUDE.md"
{ echo ""; echo "<!-- old-tool-name:frontier -->"; echo "OLD STALE BODY"; } > "$CLAUDE_MD5"

"$INSTALL" --claude-user --profile frontier --force >/dev/null
assert_true "legacy-name marker: migrated to the current marker text" \
  grep -qxF "$(marker_line frontier)" "$CLAUDE_MD5"
assert_marker_count "$CLAUDE_MD5" 2 "legacy-name marker: exactly one begin + one end marker after the same-run refresh"
assert_false "legacy-name marker: stale body refreshed away in the same run" \
  grep -q "OLD STALE BODY" "$CLAUDE_MD5"
assert_true "legacy-name marker: .bak created (it was also a no-end-marker legacy block)" \
  [ -f "${CLAUDE_MD5}.bak" ]

rm -rf "$HOME5"

# --- 11: duplicate begin marker fails loudly ---

HOME6="$TMPROOT/home6"
mkdir -p "$HOME6/.claude"
export HOME="$HOME6"
CLAUDE_MD6="$HOME6/.claude/CLAUDE.md"
{
  echo ""; marker_line frontier; echo "body one"; end_marker_line frontier
  echo ""; marker_line frontier; echo "body two"; end_marker_line frontier
} > "$CLAUDE_MD6"

if "$INSTALL" --claude-user --profile frontier --force >"$TMPROOT/dup.out" 2>&1; then
  fail "duplicate begin marker: --force should fail loudly (exited 0)"
else
  pass "duplicate begin marker: --force fails loudly (non-zero exit)"
fi
assert_true "duplicate begin marker: error message explains the refusal" grep -qi "refusing" "$TMPROOT/dup.out"

rm -rf "$HOME6"

# --- 12: symlinked CLAUDE.md stays a symlink; its target gets the content ---

HOME7="$TMPROOT/home7"
mkdir -p "$HOME7/.claude" "$TMPROOT/real"
export HOME="$HOME7"
REAL_CLAUDE_MD="$TMPROOT/real/CLAUDE.real.md"
: > "$REAL_CLAUDE_MD"
ln -s "$REAL_CLAUDE_MD" "$HOME7/.claude/CLAUDE.md"

"$INSTALL" --claude-user --profile frontier >/dev/null
assert_true "symlinked CLAUDE.md: stays a symlink after append" [ -L "$HOME7/.claude/CLAUDE.md" ]
assert_true "symlinked CLAUDE.md: real target got the appended block" \
  grep -qxF "$(marker_line frontier)" "$REAL_CLAUDE_MD"

sed -i 's/^\*\*Honesty\.\*\*.*/**Honesty.** EDITED FOR TEST./' "$REAL_CLAUDE_MD"
"$INSTALL" --claude-user --profile frontier --force >/dev/null
assert_true "symlinked CLAUDE.md: stays a symlink after --force refresh" [ -L "$HOME7/.claude/CLAUDE.md" ]
assert_false "symlinked CLAUDE.md: real target refreshed" grep -q "EDITED FOR TEST" "$REAL_CLAUDE_MD"
echo "--- ls -la proving the symlink case ---"
ls -la "$HOME7/.claude/CLAUDE.md"

rm -rf "$HOME7"

# --- 13: --dry-run writes nothing ---

HOME8="$TMPROOT/home8"
mkdir -p "$HOME8"
export HOME="$HOME8"
"$INSTALL" --claude-user --profile frontier --dry-run >/dev/null
assert_false "--dry-run: CLAUDE.md not created" [ -f "$HOME8/.claude/CLAUDE.md" ]
assert_false "--dry-run: skills/ not created" [ -d "$HOME8/.claude/skills" ]

rm -rf "$HOME8"

# --- 14: file mode is preserved across --force ---

HOME9="$TMPROOT/home9"
mkdir -p "$HOME9"
export HOME="$HOME9"
"$INSTALL" --claude-user --profile frontier >/dev/null
CLAUDE_MD9="$HOME9/.claude/CLAUDE.md"
chmod 640 "$CLAUDE_MD9"
before_mode="$(stat -c '%a' "$CLAUDE_MD9" 2>/dev/null || stat -f '%Lp' "$CLAUDE_MD9")"
"$INSTALL" --claude-user --profile frontier --force >/dev/null
after_mode="$(stat -c '%a' "$CLAUDE_MD9" 2>/dev/null || stat -f '%Lp' "$CLAUDE_MD9")"
assert_eq "$after_mode" "$before_mode" "file mode preserved across --force"

rm -rf "$HOME9"

# --- 15: --generic DIR installs AGENTS.md + skills into DIR/.agents/skills ---

GEN1="$TMPROOT/gen1"
mkdir -p "$GEN1/proj"
export HOME="$TMPROOT/home-unused-15"
"$INSTALL" --generic "$GEN1/proj" >/dev/null
assert_true "--generic: AGENTS.md written" [ -f "$GEN1/proj/AGENTS.md" ]
n_skills="$(find "$GEN1/proj/.agents/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
assert_eq "$n_skills" "34" "--generic: 34 skill dirs under DIR/.agents/skills"

"$INSTALL" --generic "$GEN1/proj" >/dev/null
n_skills_rerun="$(find "$GEN1/proj/.agents/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
assert_eq "$n_skills_rerun" "34" "--generic: idempotent re-run, still 34 skill dirs"
assert_true "--generic: idempotent re-run, AGENTS.md still present" [ -f "$GEN1/proj/AGENTS.md" ]

rm -rf "$GEN1"

# --- 16: --generic DIR --link installs skills as symlinks ---

GEN2="$TMPROOT/gen2"
mkdir -p "$GEN2/proj"
"$INSTALL" --generic "$GEN2/proj" --link >/dev/null
one_skill="$(find "$GEN2/proj/.agents/skills" -mindepth 1 -maxdepth 1 | head -n1)"
assert_true "--generic --link: skill dir is a symlink" [ -L "$one_skill" ]

rm -rf "$GEN2"

# --- 17: --generic-user installs skills into $HOME/.agents/skills, no AGENTS.md at HOME ---

HOME10="$TMPROOT/home10"
mkdir -p "$HOME10"
export HOME="$HOME10"
"$INSTALL" --generic-user >/dev/null
n_skills_user="$(find "$HOME10/.agents/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
assert_eq "$n_skills_user" "34" "--generic-user: 34 skill dirs under \$HOME/.agents/skills"
assert_false "--generic-user: no AGENTS.md written at \$HOME" [ -f "$HOME10/AGENTS.md" ]

rm -rf "$HOME10"

# --- 18: --antigravity writes .agents/{rules,workflows,skills} only, no .agent entry ---

ANTIG1="$TMPROOT/antig1"
mkdir -p "$ANTIG1/proj"
"$INSTALL" --antigravity "$ANTIG1/proj" >/dev/null
assert_true "--antigravity: .agents/rules is a real dir" [ -d "$ANTIG1/proj/.agents/rules" ]
assert_true "--antigravity: .agents/workflows is a real dir" [ -d "$ANTIG1/proj/.agents/workflows" ]
assert_true "--antigravity: .agents/skills is a real dir" [ -d "$ANTIG1/proj/.agents/skills" ]
assert_false "--antigravity: no .agent entry at all (symlink or dir)" [ -e "$ANTIG1/proj/.agent" ]

rm -rf "$ANTIG1"

# --- 19: --generic refuses a DIR inside the library — --dry-run proves a
# regressed guard would still write nothing ---

if OUT="$("$INSTALL" --generic "$LIB/skills" --dry-run 2>&1)"; then
  fail "--generic refuses a destination inside the library (subdir; exited 0, expected non-zero)"
else
  pass "--generic refuses a destination inside the library (subdir; non-zero exit)"
fi
assert_true "--generic: refusal message mentions the library (subdir)" \
  grep -q "library" <<< "$OUT"

if OUT="$("$INSTALL" --generic "$LIB" --dry-run 2>&1)"; then
  fail "--generic refuses the library root (exited 0, expected non-zero)"
else
  pass "--generic refuses the library root (non-zero exit)"
fi
assert_true "--generic: refusal message mentions the library (root)" \
  grep -q "library" <<< "$OUT"
assert_false "--generic: refused root run wrote no AGENTS.md" [ -f "$LIB/AGENTS.md" ]

# --- 20: --antigravity --force backs up an existing AGENTS.md-equivalent:
# --generic --force backs up AGENTS.md to AGENTS.md.bak ---

GEN3="$TMPROOT/gen3"
mkdir -p "$GEN3/proj"
"$INSTALL" --generic "$GEN3/proj" >/dev/null
echo "MY CUSTOM PROJECT COMMANDS" >> "$GEN3/proj/AGENTS.md"
"$INSTALL" --generic "$GEN3/proj" --force >/dev/null
assert_true "--generic --force: AGENTS.md.bak created" [ -f "$GEN3/proj/AGENTS.md.bak" ]
assert_true "--generic --force: .bak holds the pre-refresh content" \
  grep -q "MY CUSTOM PROJECT COMMANDS" "$GEN3/proj/AGENTS.md.bak"
assert_false "--generic --force: live AGENTS.md refreshed (custom line gone)" \
  grep -q "MY CUSTOM PROJECT COMMANDS" "$GEN3/proj/AGENTS.md"

rm -rf "$GEN3"

# --- 21: --agents-md is an alias for --generic (old name, same .agents/skills layout) ---

GEN4="$TMPROOT/gen4"
mkdir -p "$GEN4/proj"
"$INSTALL" --agents-md "$GEN4/proj" >/dev/null
assert_true "--agents-md (alias): AGENTS.md written" [ -f "$GEN4/proj/AGENTS.md" ]
n_skills_alias="$(find "$GEN4/proj/.agents/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
assert_eq "$n_skills_alias" "34" "--agents-md (alias): 34 skill dirs under DIR/.agents/skills"
assert_false "--agents-md (alias): no separate DIR/skills layout" [ -d "$GEN4/proj/skills" ]

rm -rf "$GEN4"

# --- 22: --antigravity migration — stale .agent -> .agents symlink is removed ---

ANTIG2="$TMPROOT/antig2"
mkdir -p "$ANTIG2/proj"
"$INSTALL" --antigravity "$ANTIG2/proj" >/dev/null
ln -s ".agents" "$ANTIG2/proj/.agent"
migrate_out="$("$INSTALL" --antigravity "$ANTIG2/proj" 2>&1)"
assert_false "--antigravity migration: stale .agent symlink removed" [ -e "$ANTIG2/proj/.agent" ]
assert_true "--antigravity migration: removal noted" \
  grep -q "removed stale .agent" <<< "$migrate_out"

rm -rf "$ANTIG2"

# --- 23: --antigravity migration — stale real .agent dir is warned about, not touched ---

ANTIG3="$TMPROOT/antig3"
mkdir -p "$ANTIG3/proj/.agent"
echo "old content" > "$ANTIG3/proj/.agent/marker.txt"
"$INSTALL" --antigravity "$ANTIG3/proj" >/dev/null
warn_out="$("$INSTALL" --antigravity "$ANTIG3/proj" 2>&1 >/dev/null)"
assert_true "--antigravity migration: stale real .agent dir warned about" \
  grep -qi "stale real directory" <<< "$warn_out"
assert_true "--antigravity migration: stale real .agent dir left untouched" \
  [ -f "$ANTIG3/proj/.agent/marker.txt" ]

rm -rf "$ANTIG3"

if [ "$FAIL" -eq 1 ]; then
  echo "test-install.sh: FAILED"
  exit 1
fi
echo "test-install.sh: all assertions passed"
