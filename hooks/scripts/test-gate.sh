#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Gates `git commit` on the project's test command.
#
# OPT-IN: does nothing unless <project>/.claude/test-command exists. That file
# contains the shell command to run (e.g. "npm test" or "pytest -q").
# Exit 0 = allow the commit. Exit 2 = block; stderr tells the model why.
# Fail-open on anything unexpected — a broken hook must not brick commits.
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

# Only care about actual commit invocations
printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)' || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GATE_FILE="$PROJECT_DIR/.claude/test-command"
[ -f "$GATE_FILE" ] || exit 0

TEST_CMD="$(head -n 1 "$GATE_FILE" | tr -d '\r')"
[ -n "$TEST_CMD" ] || exit 0

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

if (cd "$PROJECT_DIR" && bash -c "$TEST_CMD") >"$OUTPUT_FILE" 2>&1; then
  exit 0
fi

{
  echo "COMMIT BLOCKED by test gate: '$TEST_CMD' failed. Fix the failures (see below), or ask the user to remove .claude/test-command to disable this gate."
  echo "--- last 40 lines of output ---"
  tail -n 40 "$OUTPUT_FILE"
} >&2
exit 2
