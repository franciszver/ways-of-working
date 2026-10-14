#!/usr/bin/env bash
# Tests check-working-process.py against a small fixture repo built under
# mktemp. The real repo is never scanned. This file holds stale terms on
# purpose, so the check exempts it.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
check_script="$here/scripts/check-working-process.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
fixture=""
out=""

REQ='CURR-AGENT-EFFORT clean-code ste-writing plain-language. Four gates before anything merges.'

new_fixture() { # builds a clean tracked fixture repo in $fixture
  fixture="$(mktemp -d -p "$work")"
  mkdir -p "$fixture/skills/apply-working-process" "$fixture/skills-local/apply-working-process" "$fixture/docs"
  printf '%s\n' "$REQ" > "$fixture/skills/apply-working-process/SKILL.md"
  printf '%s\n' "$REQ" > "$fixture/skills-local/apply-working-process/SKILL.md"
  printf 'Plain notes.\n' > "$fixture/docs/notes.md"
  git -C "$fixture" init -q
}

track() { git -C "$fixture" add -A >/dev/null 2>&1; }

run() { # args passed to the check; sets out, returns its rc
  out="$(python3 "$check_script" "$fixture" "$@" 2>&1)"
  return $?
}

expect() { # name want_rc [grep-pattern-in-output]
  local name="$1" want="$2" pat="${3:-}" got
  run "${EXTRA_ARGS[@]}"
  got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL: $name (want rc $want, got $got)"; printf '    %s\n' "${out//$'\n'/$'\n'    }"; fail=1; return
  fi
  if [ -n "$pat" ] && ! printf '%s' "$out" | grep -q -- "$pat"; then
    echo "FAIL: $name (output lacks '$pat')"; printf '    %s\n' "${out//$'\n'/$'\n'    }"; fail=1; return
  fi
  echo "PASS: $name"
}
EXTRA_ARGS=()

old_plan="WORK""PLAN.md"
old_log="DECISIONS"".md"

new_fixture; track; expect "clean fixture passes" 0

new_fixture; printf 'Keep a %s\n' "$old_plan" > "$fixture/docs/a.md"; track
expect "stale plan file name fails" 1 "docs/a.md:1"

new_fixture; printf 'See %s\n' "$old_log" > "$fixture/docs/a.md"; track
expect "stale decision log name fails" 1 "docs/a.md"

new_fixture; printf 'old %s\n' "$old_plan" > "$fixture/CHANGELOG.md"; track
expect "exempt file passes" 0

new_fixture; printf 'old %s\n' "$old_plan" > "$fixture/CHANGELOG.mdx"; track
expect "similar name is not exempt" 1 "CHANGELOG.mdx"

new_fixture; printf 'old %s check-working-process: allow\n' "$old_plan" > "$fixture/docs/a.md"; track
expect "allow marker passes" 0

new_fixture; mkdir -p "$fixture/build"; printf 'old %s\n' "$old_plan" > "$fixture/build/x.md"; track
expect "top-level build/ is skipped" 0

new_fixture; mkdir -p "$fixture/docs/build"; printf 'old %s\n' "$old_plan" > "$fixture/docs/build/x.md"; track
expect "nested build/ is scanned" 1 "docs/build/x.md"

new_fixture; mkdir -p "$fixture/skills/local-llm-loop"; printf 'the three gates run\n' > "$fixture/skills/local-llm-loop/SKILL.md"; track
expect "local-llm-loop gate-count exemption" 0

new_fixture; mkdir -p "$fixture/skills/local-llm-loop"; printf 'keep %s\n' "$old_plan" > "$fixture/skills/local-llm-loop/SKILL.md"; track
expect "local-llm-loop is not exempt for other terms" 1

new_fixture; printf 'old %s\n' "$old_plan" > "$work/outside.md"; ln -s "$work/outside.md" "$fixture/docs/link.md"; track
expect "tracked symlink is skipped" 0

new_fixture; printf 'old %s\n' "$old_plan" > "$fixture/docs/café.md"; track
expect "non-ASCII filename is scanned" 1 "caf"

new_fixture; printf 'bad \xff\xfe bytes\n' > "$fixture/docs/bin.md"; track
expect "non-UTF-8 file fails with cause" 1 "docs/bin.md: unreadable (.*utf-8"

new_fixture; rm "$fixture/skills-local/apply-working-process/SKILL.md"; track
expect "missing required file fails" 1 "skills-local/apply-working-process/SKILL.md: missing"

new_fixture; printf 'Four gates only\n' > "$fixture/skills/apply-working-process/SKILL.md"; track
expect "missing required terms fail" 1 "lacks CURR-AGENT-EFFORT"

# New banned patterns.
i=0
while IFS= read -r text; do
  i=$((i + 1))
  new_fixture; printf '%b\n' "$text" > "$fixture/docs/p.md"; track
  expect "banned pattern $i fails" 1 "docs/p.md"
done <<'PATTERNS'
we run three gates here
we run 3 gates here
we run three\ngates here
we run 3\ngates here
see prd/DECISIONS for the log
keep a decisions log
Keeps a decision log
same-session decision logging
PATTERNS

new_fixture; printf 'Do not create a decisions log.\n' > "$fixture/docs/ok.md"; track
expect "bare decisions log wording passes" 0

# Owner file.
owner="$work/owner.md"
new_fixture; track
printf 'Keep a %s\n' "$old_plan" > "$owner"
EXTRA_ARGS=(--owner-file "$owner"); expect "owner file stale fails" 1
printf '%s\n' "$REQ" > "$owner"
expect "owner file clean passes" 0
printf 'bad \xff bytes\n' > "$owner"
expect "owner file non-UTF-8 fails with cause" 1 "unreadable"
EXTRA_ARGS=(--owner-file "$work/absent.md"); expect "owner file absent is skipped" 0
EXTRA_ARGS=()

exit "$fail"
