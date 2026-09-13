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

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$HOOK_DIR/_hook_lib.sh" ] || exit 0
# shellcheck source=./_hook_lib.sh
source "$HOOK_DIR/_hook_lib.sh"

mapfile -d '' -t FIELDS < <(read_hook_input)
EVENT_NAME="${FIELDS[0]:-PreToolUse}"
CMD="${FIELDS[1]:-}"

# Only care about actual commit invocations
printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)' || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GATE_FILE="$PROJECT_DIR/.claude/test-command"
[ -f "$GATE_FILE" ] || exit 0

TEST_CMD="$(head -n 1 "$GATE_FILE" | tr -d '\r')"
[ -n "$TEST_CMD" ] || exit 0

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

# `-o pipefail` is passed to the `bash -c` invocation itself — `set -o
# pipefail` in this script's own shell does not cross into a separate
# `bash -c` process — so a piped TEST_CMD (e.g. "npm test | tee log") fails
# the gate on the real test failure, not on `tee`'s exit code.
if (cd "$PROJECT_DIR" && bash -o pipefail -c "$TEST_CMD") >"$OUTPUT_FILE" 2>&1; then
  exit 0
fi

REASON="COMMIT BLOCKED by test gate: '$TEST_CMD' failed. Fix the failures (see below), or ask the user to remove .claude/test-command to disable this gate."
TAIL_OUTPUT="$(tail -n 40 "$OUTPUT_FILE")"
FULL_REASON="$REASON
--- last 40 lines of output ---
$TAIL_OUTPUT"

emit_decision "$EVENT_NAME" "deny" "$FULL_REASON"

{
  echo "$REASON"
  echo "--- last 40 lines of output ---"
  echo "$TAIL_OUTPUT"
} >&2
exit 2
