#!/usr/bin/env bash
# Tests check-working-process.py: --owner-file runs the same checks on a
# file outside the repo, and skips silently when the file is absent.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { # name expected_rc actual_rc
  if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (want rc $2, got $3)"; fail=1; fi
}

old_name="WORK""PLAN.md"
printf 'Keep a %s\n' "$old_name" > "$tmp/stale.md"
python3 "$here/scripts/check-working-process.py" "$here" --owner-file "$tmp/stale.md" >/dev/null
check "owner file naming the old plan file fails" 1 $?

printf 'Use docs/CURR-AGENT-EFFORT.md with clean-code, ste-writing, plain-language. Four gates.\n' > "$tmp/good.md"
python3 "$here/scripts/check-working-process.py" "$here" --owner-file "$tmp/good.md" >/dev/null
check "clean owner file passes" 0 $?

printf 'Four gates, but no effort plan terms\n' > "$tmp/missing.md"
python3 "$here/scripts/check-working-process.py" "$here" --owner-file "$tmp/missing.md" >/dev/null
check "owner file lacking required terms fails" 1 $?

python3 "$here/scripts/check-working-process.py" "$here" --owner-file "$tmp/absent.md" >/dev/null
check "absent owner file is skipped" 0 $?

exit "$fail"
