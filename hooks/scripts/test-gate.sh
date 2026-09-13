#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Gates `git commit` on the project's test command.
#
# OPT-IN: does nothing unless <project>/.claude/test-command exists. That file
# contains the shell command to run (e.g. "npm test" or "pytest -q").
# On block: prints the {"hookSpecificOutput": {"permissionDecision": "deny",
# ...}} JSON form on stdout for clients that read it, and still exits 2 with
# the output on stderr as a fallback for clients that only honor the exit code.
# Exit 0 = allow the commit.
# Fail-open on anything unexpected — a broken hook must not brick commits.
set -u

INPUT="$(cat)"

command -v python3 >/dev/null 2>&1 || exit 0

EVENT_NAME="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("hook_event_name", "PreToolUse"))
except Exception:
    print("PreToolUse")
' 2>/dev/null)"
[ -n "$EVENT_NAME" ] || EVENT_NAME="PreToolUse"

CMD="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null)" || exit 0

# Only care about actual commit invocations
printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)' || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GATE_FILE="$PROJECT_DIR/.claude/test-command"
[ -f "$GATE_FILE" ] || exit 0

TEST_CMD="$(head -n 1 "$GATE_FILE" | tr -d '\r')"
[ -n "$TEST_CMD" ] || exit 0

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

# pipefail scoped to this subshell only, so a piped TEST_CMD (e.g.
# "npm test | tee log") fails the gate on the real test failure, not on
# tee's exit code.
if (set -o pipefail; cd "$PROJECT_DIR" && bash -c "$TEST_CMD") >"$OUTPUT_FILE" 2>&1; then
  exit 0
fi

REASON="COMMIT BLOCKED by test gate: '$TEST_CMD' failed. Fix the failures (see below), or ask the user to remove .claude/test-command to disable this gate."
TAIL_OUTPUT="$(tail -n 40 "$OUTPUT_FILE")"

python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": sys.argv[1],
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[2] + "\n--- last 40 lines of output ---\n" + sys.argv[3],
    }
}))
' "$EVENT_NAME" "$REASON" "$TAIL_OUTPUT" 2>/dev/null

{
  echo "$REASON"
  echo "--- last 40 lines of output ---"
  echo "$TAIL_OUTPUT"
} >&2
exit 2
