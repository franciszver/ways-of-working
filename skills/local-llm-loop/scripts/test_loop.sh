#!/usr/bin/env bash
# Tests for run_loop.sh. Runs entirely without a live model: a dry-run
# against the bundled taskrepo fixture, and two `goose` shims on PATH
# (happy path, and a 500-then-succeed retry path) — no live model
# required.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_LOOP="$SCRIPT_DIR/run_loop.sh"
RESET_TASK="$SCRIPT_DIR/reset_task.sh"
TASK_PROMPT="$SCRIPT_DIR/task_prompt.txt"

SCRATCH="$(mktemp -d)"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# Required env vars — dry-run doesn't need real values, but run_loop.sh
# now errors out (by design) if they're unset even under --dry-run for
# the badargs/crashshim cases below, which are not --dry-run.
export OPENAI_HOST="${OPENAI_HOST:-http://127.0.0.1:8080}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-local}"
export GOOSE_MODEL="${GOOSE_MODEL:-test-model}"

PASS=0
FAIL=0
check() {
  local rc="$1" desc="$2"
  if [ "$rc" -eq 0 ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# --------------------------------------------------------------------
# 1. run_loop.sh exists and is syntactically valid.
# --------------------------------------------------------------------
[ -f "$RUN_LOOP" ]
check $? "run_loop.sh exists"

bash -n "$RUN_LOOP"
check $? "bash -n run_loop.sh passes"

# --------------------------------------------------------------------
# 2. --dry-run against the bundled taskrepo fixture.
# --------------------------------------------------------------------
echo
echo "===== (2) dry-run against fixtures/taskrepo-src ====="
DEST2="$SCRATCH/dryrun/taskrepo"
bash "$RESET_TASK" --dest "$DEST2" >/dev/null
bash "$RUN_LOOP" "$DEST2" "$TASK_PROMPT" --dry-run --max-iterations 1 \
  > "$SCRATCH/dryrun.out" 2>&1
cat "$SCRATCH/dryrun.out"

WT2="$(find "$DEST2/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
[ -n "$WT2" ] && [ -d "$WT2" ]
check $? "dry-run created a worktree under $DEST2/.loop"

git -C "$DEST2" worktree list 2>/dev/null | grep -q 'loop/'
check $? "dry-run registered a loop/<timestamp> branch worktree"

[ -f "$SCRIPT_DIR/prompts/plan.md" ] && [ -f "$SCRIPT_DIR/prompts/execute.md" ] \
  && [ -f "$SCRIPT_DIR/prompts/review.md" ] && [ -f "$SCRIPT_DIR/prompts/fix.md" ]
check $? "stage prompt files exist under scripts/prompts"

[ -n "$WT2" ] && [ -f "$WT2/.loop-run/goose-config/goose/config.yaml" ]
check $? "dry-run seeded an isolated goose config from the bundled example"

[ -n "$WT2" ] && [ -f "$WT2/TEST_OUTPUT.txt" ] && grep -q 'Ran .* tests' "$WT2/TEST_OUTPUT.txt" \
  && grep -q '^OK$' "$WT2/TEST_OUTPUT.txt"
check $? "dry-run's mechanical test stage actually ran the fixture's real tests"

# --------------------------------------------------------------------
# Shared fake-goose shim body. Reads the -i <prompt file> argument to
# tell which stage it's simulating (from the prompt filename) and
# writes that stage's expected output file(s) into the cwd (the
# worktree, since invoke_goose cd's there first). If FAIL_FIRST_CALL is
# set and SHIM_STATE_DIR/called_once does not yet exist, it emits a
# format-rejection message and fails instead, so run_loop.sh's retry
# path is exercised exactly once, on its very first goose call.
# --------------------------------------------------------------------
write_shim() {
  local path="$1"
  cat > "$path" <<'SHIM'
#!/usr/bin/env bash
set -u

if [ -n "${FAIL_FIRST_CALL:-}" ] && [ -n "${SHIM_STATE_DIR:-}" ]; then
  marker="$SHIM_STATE_DIR/called_once"
  if [ ! -f "$marker" ]; then
    mkdir -p "$SHIM_STATE_DIR"
    touch "$marker"
    echo "goose: request failed: HTTP 500 - does not match the expected peg-native format"
    exit 1
  fi
fi

prompt=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-i" ]; then
    prompt="$a"
  fi
  prev="$a"
done

case "$prompt" in
  */plan.md)
    printf '1. [ ] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: in progress\n' > HANDOFF.md
    ;;
  */execute.md)
    printf '1. [x] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  */review.md)
    printf 'no findings\n' > REVIEW.md
    ;;
  */fix.md)
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  *)
    echo "shim goose: unrecognized prompt file: $prompt" >&2
    exit 1
    ;;
esac
exit 0
SHIM
  chmod +x "$path"
}

# --------------------------------------------------------------------
# 3. Fake-goose happy path.
# --------------------------------------------------------------------
echo
echo "===== (3) fake-goose happy path ====="
DEST3="$SCRATCH/shimok/taskrepo"
bash "$RESET_TASK" --dest "$DEST3" >/dev/null
SHIMDIR3="$SCRATCH/shim-ok"
mkdir -p "$SHIMDIR3"
write_shim "$SHIMDIR3/goose"

PATH="$SHIMDIR3:$PATH" bash "$RUN_LOOP" "$DEST3" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/shim_ok.out" 2>&1
RC3=$?
cat "$SCRATCH/shim_ok.out"

WT3="$(find "$DEST3/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"

[ "$RC3" -eq 0 ]
check $? "shim-ok run exits 0"

[ -n "$WT3" ] && [ -f "$WT3/LOOP_DONE" ]
check $? "shim-ok run produced LOOP_DONE"

NCOMMITS=$(git -C "$WT3" log --oneline 2>/dev/null | wc -l | tr -d ' ')
[ "$NCOMMITS" -ge 6 ]
check $? "shim-ok run committed once per stage ($NCOMMITS commits including base)"

[ -n "$WT3" ] && [ -f "$WT3/PLAN.md" ] && ! grep -q '\[ \]' "$WT3/PLAN.md"
check $? "shim-ok run's PLAN.md ends with no unchecked steps"

# --------------------------------------------------------------------
# 4. Fake-goose 500-then-succeed retry path.
# --------------------------------------------------------------------
echo
echo "===== (4) fake-goose HTTP 500 retry path ====="
DEST4="$SCRATCH/shimretry/taskrepo"
bash "$RESET_TASK" --dest "$DEST4" >/dev/null
SHIMDIR4="$SCRATCH/shim-retry"
mkdir -p "$SHIMDIR4"
write_shim "$SHIMDIR4/goose"
STATE4="$SCRATCH/shim-retry-state"

PATH="$SHIMDIR4:$PATH" FAIL_FIRST_CALL=1 SHIM_STATE_DIR="$STATE4" \
  bash "$RUN_LOOP" "$DEST4" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/shim_retry.out" 2>&1
RC4=$?
cat "$SCRATCH/shim_retry.out"

WT4="$(find "$DEST4/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"

RETRIES=$(grep -c "retrying once" "$SCRATCH/shim_retry.out")
[ "$RETRIES" -eq 1 ]
check $? "exactly one retry was logged"

[ "$RC4" -eq 0 ]
check $? "shim-retry run still exits 0 after the retry"

[ -n "$WT4" ] && [ -f "$WT4/LOOP_DONE" ]
check $? "shim-retry run produced LOOP_DONE"

# --------------------------------------------------------------------
# 5. --max-iterations with a missing value errors immediately instead
#    of hanging (regression: a bare `shift 2` with no value argument
#    used to spin forever).
# --------------------------------------------------------------------
echo
echo "===== (5) --max-iterations with no value errors, does not hang ====="
DEST5="$SCRATCH/badargs/taskrepo"
bash "$RESET_TASK" --dest "$DEST5" >/dev/null
timeout 10 bash "$RUN_LOOP" "$DEST5" "$TASK_PROMPT" --max-iterations \
  > "$SCRATCH/badargs.out" 2>&1
RC5=$?
cat "$SCRATCH/badargs.out"
[ "$RC5" -eq 1 ]
check $? "missing --max-iterations value exits 1 (not a 124 timeout/hang)"

# --------------------------------------------------------------------
# 6. A goose stage that fails with no recognized retry/abort keyword
#    (e.g. the binary crashes without writing PLAN.md) must not be
#    reported as a pass (regression: plan_has_unchecked() used to treat
#    a missing PLAN.md as "no unchecked steps").
# --------------------------------------------------------------------
echo
echo "===== (6) goose stage failure with no PLAN.md never reports success ====="
DEST6="$SCRATCH/crashshim/taskrepo"
bash "$RESET_TASK" --dest "$DEST6" >/dev/null
SHIMDIR6="$SCRATCH/shim-crash"
mkdir -p "$SHIMDIR6"
cat > "$SHIMDIR6/goose" <<'SHIM'
#!/usr/bin/env bash
echo "goose: unexpected internal error, no output produced" >&2
exit 1
SHIM
chmod +x "$SHIMDIR6/goose"

PATH="$SHIMDIR6:$PATH" bash "$RUN_LOOP" "$DEST6" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/crashshim.out" 2>&1
RC6=$?
cat "$SCRATCH/crashshim.out"

grep -q "WARNING stage 'plan' exited" "$SCRATCH/crashshim.out"
check $? "a crashed goose stage with no known keyword is logged as a warning"

[ "$RC6" -ne 0 ]
check $? "a crashed goose stage that never wrote PLAN.md is reported as a failure, not a pass"

# --------------------------------------------------------------------
# 7. Missing required env vars error out immediately (not under
#    --dry-run, where a placeholder is tolerated).
# --------------------------------------------------------------------
echo
echo "===== (7) missing required env vars error out ====="
DEST7="$SCRATCH/noenv/taskrepo"
bash "$RESET_TASK" --dest "$DEST7" >/dev/null
env -u OPENAI_HOST -u OPENAI_API_KEY -u GOOSE_MODEL \
  bash "$RUN_LOOP" "$DEST7" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/noenv.out" 2>&1
RC7=$?
cat "$SCRATCH/noenv.out"
[ "$RC7" -eq 1 ] && grep -q "missing required environment variable" "$SCRATCH/noenv.out"
check $? "missing OPENAI_HOST/OPENAI_API_KEY/GOOSE_MODEL fails fast with a clear message"

# --------------------------------------------------------------------
echo
echo "===== tree scripts/ ====="
if command -v tree >/dev/null 2>&1; then
  tree "$SCRIPT_DIR"
else
  find "$SCRIPT_DIR" | sed "s|$SCRIPT_DIR/||"
fi

echo
echo "===== summary: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
