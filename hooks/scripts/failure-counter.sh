#!/usr/bin/env bash
# PostToolUseFailure hook (matcher: Bash). Appends every failed command to
# .claude/failure-log and, once the SAME command has failed twice in a
# row, prints a reminder to Claude: "same fix failing twice means the
# hypothesis is wrong" (see CLAUDE.md's Debugging rule).
# Never blocks: exit 0 always. Fail-open on anything unexpected — a
# broken hook must not interrupt the session.
set -u

INPUT="$(cat)"

command -v python3 >/dev/null 2>&1 || exit 0

CMD="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null)" || exit 0

[ -n "$CMD" ] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOG_FILE="$PROJECT_DIR/.claude/failure-log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || exit 0

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\t%s\n' "$TIMESTAMP" "$CMD" >> "$LOG_FILE" 2>/dev/null || exit 0

# Consecutive-failure count: walk the log backwards while the command matches.
COUNT="$(tac "$LOG_FILE" 2>/dev/null | awk -F'\t' -v cmd="$CMD" '
  $2 == cmd { n++; next }
  { exit }
  END { print n+0 }
')"

if [ "${COUNT:-0}" -ge 2 ]; then
  REASON="Same command has now failed $COUNT times in a row: $CMD — the same fix failing twice means the hypothesis is wrong. Stop, re-read the full error, and re-plan instead of retrying."
  python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUseFailure",
        "permissionDecision": "undecided",
        "systemMessage": sys.argv[1],
    }
}))
' "$REASON" 2>/dev/null || true
fi

exit 0
