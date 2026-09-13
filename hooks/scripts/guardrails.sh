#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Blocks a short list of catastrophic commands.
# On block: prints the {"hookSpecificOutput": {"permissionDecision": "deny",
# ...}} JSON form on stdout for clients that read it, and still exits 2 with
# the reason on stderr as a fallback for clients that only honor the exit
# code. Exit 0 = allow.
# Fail-open by design: if parsing is impossible, allow rather than brick the session.
set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$HOOK_DIR/_hook_lib.sh" ] || exit 0
# shellcheck source=./_hook_lib.sh
source "$HOOK_DIR/_hook_lib.sh"

mapfile -d '' -t FIELDS < <(read_hook_input)
EVENT_NAME="${FIELDS[0]:-PreToolUse}"
CMD="${FIELDS[1]:-}"

[ -n "$CMD" ] || exit 0

block() {
  local reason="BLOCKED by guardrails hook: $1. If this is genuinely intended, the user must run it themselves in a terminal."
  emit_decision "$EVENT_NAME" "deny" "$reason"
  echo "$reason" >&2
  exit 2
}

# Recursive delete of root, root glob, or home
if printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rf][a-zA-Z]*[[:space:]]+)+("?\$HOME"?|~|/|/\*)[[:space:]]*($|[;&|])'; then
  block "recursive delete of / or the home directory"
fi

# Force-push to main/master (branch argument or refspec destination)
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+push[[:space:]]+.*(--force([^-]|$)|-f([[:space:]]|$)).*([[:space:]]|:)(main|master)([[:space:]]|$)'; then
  block "force-push to main/master (use --force-with-lease on a feature branch instead)"
fi
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+push[[:space:]]+.*([[:space:]]|:)(main|master)([[:space:]]|$).*(--force([^-]|$)|-f([[:space:]]|$))'; then
  block "force-push to main/master (use --force-with-lease on a feature branch instead)"
fi

# Writing to raw block devices / filesystem creation
if printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])(mkfs(\.[a-z0-9]+)?[[:space:]]|dd[[:space:]]+[^;|&]*of=/dev/(sd|nvme|disk|hd))'; then
  block "raw disk write / filesystem creation"
fi

# World-writable permissions from the root
if printf '%s' "$CMD" | grep -Eq 'chmod[[:space:]]+(-[a-zA-Z]*R[a-zA-Z]*[[:space:]]+)+777[[:space:]]+/([[:space:]]|$)'; then
  block "chmod -R 777 on /"
fi

# Classic fork bomb
if printf '%s' "$CMD" | grep -q ':(){ :|:& };:'; then
  block "fork bomb"
fi

exit 0
