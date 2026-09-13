#!/usr/bin/env bash
# PostToolUseFailure hook (matcher: Bash). Opt-in via install.sh --hooks;
# NOT shipped by the plugin — it writes repo-resident content
# (.claude/failure-log; see scripts/merge-hooks.py's PLUGIN_EXCLUDED_SCRIPTS
# and hooks/README.md).
#
# Appends every failed command to .claude/failure-log, keyed by a sha1 hash
# of the full command (a hash catches a match even for a long or multi-line
# command, though only its first line is logged for readability). Once the
# same hash has failed twice in a row, adds a reminder via
# additionalContext/systemMessage: "same fix failing twice means the
# hypothesis is wrong" (see CLAUDE.md's Debugging rule).
# Never blocks: exit 0 always. Fail-open on anything unexpected.
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$HOOK_DIR/_hook_lib.sh" ] || exit 0
# shellcheck source=./_hook_lib.sh
source "$HOOK_DIR/_hook_lib.sh"

mapfile -d '' -t FIELDS < <(read_hook_input)
CMD="${FIELDS[1]:-}"
[ -n "$CMD" ] || exit 0

HASH=""
if command -v sha1sum >/dev/null 2>&1; then
  HASH="$(printf '%s' "$CMD" | sha1sum | cut -d' ' -f1)"
elif command -v shasum >/dev/null 2>&1; then
  HASH="$(printf '%s' "$CMD" | shasum -a 1 | cut -d' ' -f1)"
fi
[ -n "$HASH" ] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOG_FILE="$PROJECT_DIR/.claude/failure-log"

# Refuse to write through a symlink — never follow one to write outside
# the project directory.
[ -L "$LOG_FILE" ] && exit 0

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || exit 0

FIRST_LINE="$(printf '%s' "$CMD" | head -n 1)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\t%s\t%s\n' "$TIMESTAMP" "$HASH" "$FIRST_LINE" >> "$LOG_FILE" 2>/dev/null || exit 0

# Cap the log at its last 200 lines after every write.
LOG_LINES="$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)"
if [ "${LOG_LINES:-0}" -gt 200 ] && [ ! -L "$LOG_FILE" ]; then
  TMP_LOG="$(mktemp "${LOG_FILE}.XXXXXX")" && tail -n 200 "$LOG_FILE" > "$TMP_LOG" && mv "$TMP_LOG" "$LOG_FILE"
fi

# Consecutive-failure count: walk the log backwards while the hash
# matches, using awk alone (no tac, for portability).
COUNT="$(awk -F'\t' -v hash="$HASH" '
  { lines[NR] = $2 }
  END {
    n = 0
    for (i = NR; i >= 1; i--) {
      if (lines[i] == hash) { n++ } else { break }
    }
    print n
  }
' "$LOG_FILE" 2>/dev/null)"

if [ "${COUNT:-0}" -ge 2 ]; then
  REASON="Same command has now failed $COUNT times in a row: $FIRST_LINE — the same fix failing twice means the hypothesis is wrong. Stop, re-read the full error, and re-plan instead of retrying."
  python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUseFailure",
        "additionalContext": reason,
    },
    "systemMessage": reason,
}))
' "$REASON" 2>/dev/null || true
fi

exit 0
