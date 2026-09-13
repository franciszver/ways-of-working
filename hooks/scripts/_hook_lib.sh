#!/usr/bin/env bash
# _hook_lib.sh — shared helpers for guardrails.sh, test-gate.sh, and
# failure-counter.sh. Source it; do not execute it directly.
#
# Requires python3; callers must check `command -v python3` themselves
# before sourcing/calling into this file, and treat an empty CMD as "skip,
# fail open" — this file never exits or blocks on its own.

# read_hook_input — reads the hook's stdin JSON exactly once and prints two
# NUL-terminated fields: the hook_event_name, then tool_input.command.
# Use with `mapfile -d '' -t fields < <(read_hook_input)` so a command
# containing newlines is captured intact.
read_hook_input() {
  python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
sys.stdout.write(str(data.get("hook_event_name", "PreToolUse")) + "\0")
sys.stdout.write(str(data.get("tool_input", {}).get("command", "")) + "\0")
'
}

# emit_decision EVENT DECISION REASON — prints the documented
# hookSpecificOutput.permissionDecision JSON on stdout
# (https://code.claude.com/docs/en/hooks). DECISION is "allow", "deny", or
# "undecided". Callers still exit 2 on their own as a fallback for clients
# that only honor the exit code.
emit_decision() {
  local event="$1" decision="$2" reason="$3"
  python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": sys.argv[1],
        "permissionDecision": sys.argv[2],
        "permissionDecisionReason": sys.argv[3],
    }
}))
' "$event" "$decision" "$reason" 2>/dev/null
}
