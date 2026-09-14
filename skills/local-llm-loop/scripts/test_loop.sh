#!/usr/bin/env bash
# Tests for run_loop.sh. Runs entirely without a live model: a dry-run
# against the bundled taskrepo fixture, and several `goose`/harness
# shims on PATH (happy path, a 500-then-succeed retry path, a
# non-goose harness, and a two-iteration review-diff path) — no live
# model required.
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

# --------------------------------------------------------------------
# Assert vocabulary — same shape as scripts/test-install.sh, so both
# test scripts read the same way.
# --------------------------------------------------------------------
PASS=0
FAIL=0
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

assert_eq() { # $1 = actual, $2 = expected, $3 = description
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

assert_true() { # $1 = description, $2.. = condition command; passes if it exits 0
  local desc="$1"
  shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}

file_has() { grep -q -- "$2" "$1" 2>/dev/null; } # $1 = file, $2 = pattern
file_lacks() { ! grep -q -- "$2" "$1" 2>/dev/null; } # $1 = file, $2 = pattern
export -f file_has file_lacks # visible inside the `bash -c` probes below

# --------------------------------------------------------------------
# 1. run_loop.sh exists and is syntactically valid.
# --------------------------------------------------------------------
assert_true "run_loop.sh exists" [ -f "$RUN_LOOP" ]

bash -n "$RUN_LOOP"
assert_eq "$?" "0" "bash -n run_loop.sh passes"

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
assert_true "dry-run created a worktree under $DEST2/.loop" bash -c '[ -n "$1" ] && [ -d "$1" ]' _ "$WT2"

git -C "$DEST2" worktree list 2>/dev/null | grep -q 'loop/'
assert_eq "$?" "0" "dry-run registered a loop/<timestamp> branch worktree"

assert_true "stage prompt files exist under scripts/prompts" bash -c '
  [ -f "$1/plan.md" ] && [ -f "$1/execute.md" ] && [ -f "$1/review.md" ] && [ -f "$1/fix.md" ] && [ -f "$1/common-rules.md" ]
' _ "$SCRIPT_DIR/prompts"

assert_true "dry-run seeded an isolated goose config from the bundled example" bash -c '[ -n "$1" ] && [ -f "$1/.loop-run/goose-config/goose/config.yaml" ]' _ "$WT2"

assert_true "dry-run's mechanical test stage actually ran the fixture's real tests" bash -c '
  [ -n "$1" ] && [ -f "$1/TEST_OUTPUT.txt" ] && grep -q "Ran .* tests" "$1/TEST_OUTPUT.txt" && grep -q "^OK$" "$1/TEST_OUTPUT.txt"
' _ "$WT2"

# --------------------------------------------------------------------
# Shared fake-goose shim body. Reads the -i <prompt file> argument to
# tell which stage it's simulating (from the prompt filename) and
# writes that stage's expected output file(s) into the cwd (the
# worktree, since invoke_goose cd's there first). If FAIL_FIRST_CALL is
# set and SHIM_STATE_DIR/called_once does not yet exist, it emits a
# format-rejection message and fails instead, so run_loop.sh's retry
# path is exercised exactly once, on its very first goose call. Every
# stage prompt now has common-rules.md appended, so matching is still
# by the stage prompt's basename, not exact content.
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
  */plan_prompt.md)
    printf '1. [ ] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: in progress\n' > HANDOFF.md
    ;;
  */execute_prompt.md)
    printf '1. [x] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  */review_prompt.md)
    printf 'no findings\n' > REVIEW.md
    ;;
  */fix_prompt.md)
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

assert_eq "$RC3" "0" "shim-ok run exits 0"

assert_true "shim-ok run produced LOOP_DONE" bash -c '[ -n "$1" ] && [ -f "$1/LOOP_DONE" ]' _ "$WT3"

NCOMMITS=$(git -C "$WT3" log --oneline 2>/dev/null | wc -l | tr -d ' ')
assert_true "shim-ok run committed once per stage ($NCOMMITS commits including base)" [ "$NCOMMITS" -ge 6 ]

assert_true "shim-ok run's PLAN.md ends with no unchecked steps" bash -c '[ -n "$1" ] && [ -f "$1/PLAN.md" ] && ! grep -q "\[ \]" "$1/PLAN.md"' _ "$WT3"

# NEXT_STEP.md (finding 8): the driver extracts the first unchecked
# PLAN.md step into NEXT_STEP.md for execute.md to read, before running
# the execute stage.
assert_true "NEXT_STEP.md contains the first unchecked step from PLAN.md" bash -c '[ -n "$1" ] && file_has "$1/NEXT_STEP.md" "1. \[ \] do the thing"' _ "$WT3"

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
assert_eq "$RETRIES" "1" "exactly one retry was logged"

assert_eq "$RC4" "0" "shim-retry run still exits 0 after the retry"

assert_true "shim-retry run produced LOOP_DONE" bash -c '[ -n "$1" ] && [ -f "$1/LOOP_DONE" ]' _ "$WT4"

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
assert_eq "$RC5" "1" "missing --max-iterations value exits 1 (not a 124 timeout/hang)"

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
assert_eq "$?" "0" "a crashed goose stage with no known keyword is logged as a warning"

assert_true "a crashed goose stage that never wrote PLAN.md is reported as a failure, not a pass" [ "$RC6" -ne 0 ]

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
assert_true "missing OPENAI_HOST/OPENAI_API_KEY/GOOSE_MODEL fails fast with a clear message" bash -c '
  [ "$1" -eq 1 ] && grep -q "missing required environment variable" "$2"
' _ "$RC7" "$SCRATCH/noenv.out"

# --------------------------------------------------------------------
# 8. Harness seam (finding 5): LOOP_HARNESS_CMD points at a non-goose
#    shim and the loop still runs it, with {prompt} substituted.
# --------------------------------------------------------------------
echo
echo "===== (8) LOOP_HARNESS_CMD points at a non-goose shim ====="
DEST8="$SCRATCH/harness/taskrepo"
bash "$RESET_TASK" --dest "$DEST8" >/dev/null
SHIMDIR8="$SCRATCH/shim-harness"
mkdir -p "$SHIMDIR8"
write_shim "$SHIMDIR8/custom-harness"

LOOP_HARNESS_CMD="$SHIMDIR8/custom-harness -i {prompt}" \
  bash "$RUN_LOOP" "$DEST8" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/harness.out" 2>&1
RC8=$?
cat "$SCRATCH/harness.out"

WT8="$(find "$DEST8/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"

assert_eq "$RC8" "0" "LOOP_HARNESS_CMD shim run exits 0"
assert_true "LOOP_HARNESS_CMD shim run produced LOOP_DONE" bash -c '[ -n "$1" ] && [ -f "$1/LOOP_DONE" ]' _ "$WT8"

# --------------------------------------------------------------------
# 9. Review diff covers only the delta since the last review (finding
#    7): two iterations, each with the execute shim touching a
#    different file, and each review-stage commit's DIFF.txt snapshot
#    should show only that iteration's file.
# --------------------------------------------------------------------
echo
echo "===== (9) review diff covers only the delta since the last review ====="
DEST9="$SCRATCH/reviewdiff/taskrepo"
bash "$RESET_TASK" --dest "$DEST9" >/dev/null
SHIMDIR9="$SCRATCH/shim-reviewdiff"
mkdir -p "$SHIMDIR9"
STATE9="$SCRATCH/shim-reviewdiff-state"
mkdir -p "$STATE9"
cat > "$SHIMDIR9/goose" <<'SHIM'
#!/usr/bin/env bash
set -u
STATE_DIR="${SHIM_STATE_DIR:?}"
COUNTER_FILE="$STATE_DIR/execute_count"

prompt=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-i" ]; then prompt="$a"; fi
  prev="$a"
done

case "$prompt" in
  */plan_prompt.md)
    printf '1. [ ] step one\n2. [ ] step two\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: in progress\n' > HANDOFF.md
    ;;
  */execute_prompt.md)
    n=0
    [ -f "$COUNTER_FILE" ] && n="$(cat "$COUNTER_FILE")"
    n=$((n + 1))
    echo "$n" > "$COUNTER_FILE"
    if [ "$n" -eq 1 ]; then
      echo "iteration one" > file1.txt
      printf '1. [x] step one\n2. [ ] step two\n' > PLAN.md
    else
      echo "iteration two" > file2.txt
      printf '1. [x] step one\n2. [x] step two\n' > PLAN.md
    fi
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  */review_prompt.md)
    # Snapshot what this review actually saw, tagged by the execute
    # counter, so the test can compare iteration 1's delta against
    # iteration 2's once the run has moved on and overwritten the live
    # .loop-run/DIFF.txt.
    n=0
    [ -f "$COUNTER_FILE" ] && n="$(cat "$COUNTER_FILE")"
    cp .loop-run/DIFF.txt "$STATE_DIR/diff_seen_${n}.txt" 2>/dev/null || true
    printf 'no findings\n' > REVIEW.md
    ;;
  */fix_prompt.md)
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  *)
    echo "shim goose: unrecognized prompt file: $prompt" >&2
    exit 1
    ;;
esac
exit 0
SHIM
chmod +x "$SHIMDIR9/goose"

PATH="$SHIMDIR9:$PATH" SHIM_STATE_DIR="$STATE9" \
  bash "$RUN_LOOP" "$DEST9" "$TASK_PROMPT" --max-iterations 2 \
  > "$SCRATCH/reviewdiff.out" 2>&1
RC9=$?
cat "$SCRATCH/reviewdiff.out"

WT9="$(find "$DEST9/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
assert_eq "$RC9" "0" "review-diff run exits 0"

REVIEW_COUNT=$(git -C "$WT9" log --oneline --grep='^loop: review' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$REVIEW_COUNT" "2" "review-diff run made two review-stage commits"

assert_true "first review's diff covers file1.txt" file_has "$STATE9/diff_seen_1.txt" "file1.txt"
assert_true "second review's diff covers file2.txt" file_has "$STATE9/diff_seen_2.txt" "file2.txt"
assert_true "second review's diff excludes file1.txt (delta only, not the whole run)" file_lacks "$STATE9/diff_seen_2.txt" "file1.txt"

assert_true "FULL_DIFF.txt covers both file1.txt and file2.txt" bash -c '
  [ -n "$1" ] && [ -f "$1/.loop-run/FULL_DIFF.txt" ] && file_has "$1/.loop-run/FULL_DIFF.txt" file1.txt && file_has "$1/.loop-run/FULL_DIFF.txt" file2.txt
' _ "$WT9"

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
