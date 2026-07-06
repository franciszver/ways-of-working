#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Blocks a short list of catastrophic commands.
# Exit 0 = allow. Exit 2 = block; stderr is shown to the model as the reason.
# Fail-open by design: if parsing is impossible, allow rather than brick the session.
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

block() {
  echo "BLOCKED by guardrails hook: $1. If this is genuinely intended, the user must run it themselves in a terminal." >&2
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
