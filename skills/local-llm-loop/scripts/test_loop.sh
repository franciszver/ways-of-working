#!/usr/bin/env bash
# Tests for run_loop.sh. Runs entirely without a live model: a dry-run
# against the bundled taskrepo fixture, and one shared `goose`/harness
# shim on PATH driven by env knobs (happy path, a 500-then-succeed
# retry path, a non-goose harness, gate order, findings filter, delete
# guard, convergence cap, nudged retry, per-file split) plus two
# specialized shims (a two-iteration review-diff path and an argv
# quoting probe) — no live model required.
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

# Outer test-harness timeout bound. Stock macOS ships no `timeout`, so
# use the same fallback chain run_loop.sh itself uses.
if command -v timeout >/dev/null 2>&1; then
  tmo() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
  tmo() { gtimeout "$@"; }
else
  tmo() { perl -e 'alarm shift; exec @ARGV' -- "$@"; }
fi

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

# Builds a PATH directory that mirrors every command reachable on the
# current $PATH except the given names, by symlinking each first-found
# executable into $1 (skipping names already linked, to preserve PATH
# lookup precedence). Used to prove the portable-timeout and
# portable-realpath-resolution fallbacks actually run when the GNU-only
# tool they'd normally use isn't there — not just that the fallback
# code path exists.
build_path_without() {
  local dest="$1"
  shift
  local skip=("$@")
  mkdir -p "$dest"
  local dir f base skipped
  local saved_ifs="$IFS"
  IFS=':'
  for dir in $PATH; do
    IFS="$saved_ifs"
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      base="$(basename "$f")"
      [ -e "$dest/$base" ] && continue
      skipped=false
      for s in "${skip[@]}"; do
        [ "$base" = "$s" ] && skipped=true && break
      done
      $skipped && continue
      ln -s "$f" "$dest/$base" 2>/dev/null || true
    done
    IFS=':'
  done
  IFS="$saved_ifs"
}

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
  [ -f "$1/plan.md" ] && [ -f "$1/execute.md" ] && [ -f "$1/simplify.md" ] && [ -f "$1/security.md" ] && [ -f "$1/review.md" ] && [ -f "$1/fix.md" ] && [ -f "$1/common-rules.md" ] && [ -f "$1/gate-rules.md" ]
' _ "$SCRIPT_DIR/prompts"

assert_true "dry-run seeded an isolated goose config from the bundled example" bash -c '[ -n "$1" ] && [ -f "$1/.loop-run/goose-config/goose/config.yaml" ]' _ "$WT2"

assert_true "dry-run's mechanical test stage actually ran the fixture's real tests" bash -c '
  [ -n "$1" ] && [ -f "$1/TEST_OUTPUT.txt" ] && grep -q "Ran .* tests" "$1/TEST_OUTPUT.txt" && grep -q "^OK$" "$1/TEST_OUTPUT.txt"
' _ "$WT2"

# --------------------------------------------------------------------
# The shared fake-goose shim. Reads the -i <prompt file> argument to
# tell which stage it is simulating (from the prompt filename; the
# stage prompt has common-rules.md appended and a retry is named
# *_prompt_retry.md, so matching is on the basename prefix) and writes
# that stage's expected output file(s) into the cwd (the worktree).
# Records every stage it is called for, in order, in
# $SHIM_STATE_DIR/stages (default: .loop-run/shim-state in the
# worktree, gitignored). Env knobs:
#   FAIL_FIRST_CALL   emit a format-rejection and exit 1 on the very
#                     first call only, to exercise the retry path once
#   GATE_REVIEW_OUT   text the review gate writes to REVIEW.md; unset
#                     means "no findings"; set but empty means write
#                     nothing at all (prose instead of a call)
#   REVIEW_SKIP_FIRST when set, the review gate writes nothing on its
#                     first call only, then behaves normally
#   FIX_DELETES       when set, the fix stage deletes this file
# --------------------------------------------------------------------
write_gate_shim() {
  local path="$1"
  cat > "$path" <<'SHIM'
#!/usr/bin/env bash
set -u
STATE_DIR="${SHIM_STATE_DIR:-.loop-run/shim-state}"
mkdir -p "$STATE_DIR"

if [ -n "${FAIL_FIRST_CALL:-}" ] && [ ! -f "$STATE_DIR/called_once" ]; then
  touch "$STATE_DIR/called_once"
  echo "goose: request failed: HTTP 500 - does not match the expected peg-native format"
  exit 1
fi
prompt=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-i" ]; then prompt="$a"; fi
  prev="$a"
done
stage="$(basename "$prompt" | sed 's/_prompt.*//')"
echo "$stage" >> "$STATE_DIR/stages"
cp .loop-run/DIFF.txt "$STATE_DIR/diff_seen_$(wc -l < "$STATE_DIR/stages" | tr -d ' ')_$stage.txt" 2>/dev/null || true
case "$stage" in
  plan)
    printf '1. [ ] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: in progress\n' > HANDOFF.md
    ;;
  execute)
    echo "new code" > new_a.txt
    echo "new code" > new_b.txt
    printf '1. [x] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  simplify)  printf 'no findings\n' > SIMPLIFY.md ;;
  security)  printf 'no findings\n' > SECURITY.md ;;
  review)
    if [ -n "${REVIEW_SKIP_FIRST:-}" ] && [ ! -f "$STATE_DIR/review_skipped" ]; then
      touch "$STATE_DIR/review_skipped"
      echo "I looked at the diff and it seems fine." # prose, no file written
    elif [ -n "${GATE_REVIEW_OUT-no findings}" ]; then
      # Unset: a clean review. Set but empty: write nothing at all.
      printf '%b\n' "${GATE_REVIEW_OUT-no findings\nclean}" > REVIEW.md
    fi
    ;;
  fix)
    cp FINDINGS.md "$STATE_DIR/findings_seen_$(wc -l < "$STATE_DIR/stages" | tr -d ' ').md"
    if [ -n "${FIX_DELETES:-}" ]; then rm -f "$FIX_DELETES"; fi
    printf '# Handoff: test\nUpdated: now - State: fixed\n' > HANDOFF.md
    ;;
  *) echo "gate shim: unrecognized stage '$stage' from $prompt" >&2; exit 1 ;;
esac
exit 0
SHIM
  chmod +x "$path"
}

run_gate_case() { # $1 = case name; remaining args passed to run_loop.sh
  local name="$1"; shift
  local dest="$SCRATCH/$name/taskrepo" shimdir="$SCRATCH/shim-$name"
  bash "$RESET_TASK" --dest "$dest" >/dev/null
  mkdir -p "$shimdir"
  write_gate_shim "$shimdir/goose"
  PATH="$shimdir:$PATH" SHIM_STATE_DIR="$SCRATCH/state-$name" \
    bash "$RUN_LOOP" "$dest" "$TASK_PROMPT" "$@" > "$SCRATCH/$name.out" 2>&1
  echo "$?" > "$SCRATCH/$name.rc"
  cat "$SCRATCH/$name.out"
}
wt_of() { find "$SCRATCH/$1/taskrepo/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1; }
stages_of() { tr '\n' ' ' < "$SCRATCH/state-$1/stages" | sed 's/ $//'; }

# --------------------------------------------------------------------
# 3. Fake-goose happy path.
# --------------------------------------------------------------------
echo
echo "===== (3) fake-goose happy path ====="
DEST3="$SCRATCH/shimok/taskrepo"
bash "$RESET_TASK" --dest "$DEST3" >/dev/null
SHIMDIR3="$SCRATCH/shim-ok"
mkdir -p "$SHIMDIR3"
write_gate_shim "$SHIMDIR3/goose"

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
write_gate_shim "$SHIMDIR4/goose"
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
tmo 10 bash "$RUN_LOOP" "$DEST5" "$TASK_PROMPT" --max-iterations \
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
write_gate_shim "$SHIMDIR8/custom-harness"

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
  */plan_prompt*.md)
    printf '1. [ ] step one\n2. [ ] step two\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: in progress\n' > HANDOFF.md
    ;;
  */execute_prompt*.md)
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
  */simplify_prompt*.md)
    printf 'no findings\n' > SIMPLIFY.md
    ;;
  */security_prompt*.md)
    printf 'no findings\n' > SECURITY.md
    ;;
  */review_prompt*.md)
    # Snapshot what this review actually saw, tagged by the execute
    # counter, so the test can compare iteration 1's delta against
    # iteration 2's once the run has moved on and overwritten the live
    # .loop-run/DIFF.txt.
    n=0
    [ -f "$COUNTER_FILE" ] && n="$(cat "$COUNTER_FILE")"
    cp .loop-run/DIFF.txt "$STATE_DIR/diff_seen_${n}.txt" 2>/dev/null || true
    printf 'no findings\n' > REVIEW.md
    ;;
  */fix_prompt*.md)
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
# 10. Portable timeout: with `timeout` and `gtimeout` both hidden from
#     PATH, run_loop.sh must fall back to its perl-alarm path.
#     (a) A normal shim run still completes end to end on the fallback.
#     (b) A deliberately slow shim gets killed at LOOP_STAGE_TIMEOUT and
#         the perl-alarm exit (142) is mapped to 124, same as `timeout`.
# --------------------------------------------------------------------
echo
echo "===== (10) perl-alarm fallback when timeout/gtimeout are both absent ====="
NOTIMEOUT_PATH="$SCRATCH/path-no-timeout"
build_path_without "$NOTIMEOUT_PATH" timeout gtimeout
PATH="$NOTIMEOUT_PATH" bash -c 'command -v timeout >/dev/null 2>&1'
assert_eq "$?" "1" "PATH() lookup: no-timeout PATH truly hides timeout"
PATH="$NOTIMEOUT_PATH" bash -c 'command -v gtimeout >/dev/null 2>&1'
assert_eq "$?" "1" "PATH() lookup: no-timeout PATH truly hides gtimeout"
PATH="$NOTIMEOUT_PATH" bash -c 'command -v perl >/dev/null 2>&1'
assert_eq "$?" "0" "PATH() lookup: no-timeout PATH still has perl"

echo
echo "----- (10a) happy path runs to completion on the perl fallback -----"
DEST10A="$SCRATCH/notimeout-ok/taskrepo"
bash "$RESET_TASK" --dest "$DEST10A" >/dev/null
SHIMDIR10A="$SCRATCH/shim-notimeout-ok"
mkdir -p "$SHIMDIR10A"
write_gate_shim "$SHIMDIR10A/goose"

PATH="$SHIMDIR10A:$NOTIMEOUT_PATH" bash "$RUN_LOOP" "$DEST10A" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/notimeout_ok.out" 2>&1
RC10A=$?
cat "$SCRATCH/notimeout_ok.out"

WT10A="$(find "$DEST10A/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
assert_eq "$RC10A" "0" "perl-fallback run (no timeout/gtimeout on PATH) exits 0"
assert_true "perl-fallback run produced LOOP_DONE" bash -c '[ -n "$1" ] && [ -f "$1/LOOP_DONE" ]' _ "$WT10A"

echo
echo "----- (10b) a slow stage is killed at the limit, exit code mapped to 124 -----"
DEST10B="$SCRATCH/notimeout-slow/taskrepo"
bash "$RESET_TASK" --dest "$DEST10B" >/dev/null
SHIMDIR10B="$SCRATCH/shim-notimeout-slow"
mkdir -p "$SHIMDIR10B"
cat > "$SHIMDIR10B/goose" <<'SHIM'
#!/usr/bin/env bash
sleep 30
SHIM
chmod +x "$SHIMDIR10B/goose"

START10B=$(date +%s)
PATH="$SHIMDIR10B:$NOTIMEOUT_PATH" LOOP_STAGE_TIMEOUT=1 \
  tmo 20 bash "$RUN_LOOP" "$DEST10B" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/notimeout_slow.out" 2>&1
END10B=$(date +%s)
cat "$SCRATCH/notimeout_slow.out"

ELAPSED10B=$((END10B - START10B))
assert_true "the slow stage was killed near the 1s limit, not left to run 30s ($ELAPSED10B s elapsed)" [ "$ELAPSED10B" -lt 15 ]

grep -q "WARNING stage 'plan' exited 124" "$SCRATCH/notimeout_slow.out"
assert_eq "$?" "0" "the perl-alarm kill (142) was mapped to exit code 124, matching timeout's contract"

# --------------------------------------------------------------------
# 11. reset_task.sh must resolve its destination without GNU `realpath
#     -m` (BSD realpath rejects -m, and the flag can't be relied on to
#     exist at all) — run it with realpath removed from PATH entirely.
# --------------------------------------------------------------------
echo
echo "===== (11) reset_task.sh resolves its destination with realpath absent from PATH ====="
NOREALPATH_PATH="$SCRATCH/path-no-realpath"
build_path_without "$NOREALPATH_PATH" realpath
PATH="$NOREALPATH_PATH" bash -c 'command -v realpath >/dev/null 2>&1'
assert_eq "$?" "1" "PATH() lookup: no-realpath PATH truly hides realpath"

DEST11="$SCRATCH/norealpath/taskrepo"
PATH="$NOREALPATH_PATH" bash "$RESET_TASK" --dest "$DEST11" > "$SCRATCH/norealpath.out" 2>&1
RC11=$?
cat "$SCRATCH/norealpath.out"
assert_eq "$RC11" "0" "reset_task.sh succeeds with realpath absent from PATH"
assert_true "reset_task.sh built the work copy at the requested dest" [ -d "$DEST11" ]
assert_true "reset_task.sh committed a clean-state baseline" bash -c '
  git -C "$1" log --oneline 2>/dev/null | grep -q "clean state"
' _ "$DEST11"

# Same guard, still enforced without realpath: a --dest with no
# "taskrepo" path segment must still be refused, not silently resolved.
DEST11BAD="$SCRATCH/norealpath-bad/notarepo"
PATH="$NOREALPATH_PATH" bash "$RESET_TASK" --dest "$DEST11BAD" > "$SCRATCH/norealpath_bad.out" 2>&1
RC11BAD=$?
cat "$SCRATCH/norealpath_bad.out"
assert_true "reset_task.sh still refuses a --dest with no 'taskrepo' segment (realpath absent)" [ "$RC11BAD" -ne 0 ]
assert_true "the refused dest was never created" [ ! -d "$DEST11BAD" ]

# --------------------------------------------------------------------
# 12. LOOP_HARNESS_CMD template quoting: a quoted multi-word argument in
#     the template must reach the harness as one argv entry, not be
#     mangled by whitespace splitting.
# --------------------------------------------------------------------
echo
echo "===== (12) LOOP_HARNESS_CMD honors shell quoting in the template ====="
DEST12="$SCRATCH/quoting/taskrepo"
bash "$RESET_TASK" --dest "$DEST12" >/dev/null
SHIMDIR12="$SCRATCH/shim-quoting"
mkdir -p "$SHIMDIR12"
ARGV_DUMP="$SCRATCH/argv_dump.txt"
cat > "$SHIMDIR12/shim.sh" <<'SHIM'
#!/usr/bin/env bash
: > "$ARGV_DUMP"
for a in "$@"; do
  printf '%s\n' "$a" >> "$ARGV_DUMP"
done
prompt=""
for a in "$@"; do prompt="$a"; done
case "$prompt" in
  */plan_prompt*.md)
    printf '1. [ ] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: in progress\n' > HANDOFF.md
    ;;
  */execute_prompt*.md)
    printf '1. [x] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  */simplify_prompt*.md)
    printf 'no findings\n' > SIMPLIFY.md
    ;;
  */security_prompt*.md)
    printf 'no findings\n' > SECURITY.md
    ;;
  */review_prompt*.md)
    printf 'no findings\n' > REVIEW.md
    ;;
  */fix_prompt*.md)
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
esac
exit 0
SHIM
chmod +x "$SHIMDIR12/shim.sh"

export ARGV_DUMP
LOOP_HARNESS_CMD="$SHIMDIR12/shim.sh --flag \"quoted value\" {prompt}" \
  bash "$RUN_LOOP" "$DEST12" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/quoting.out" 2>&1
RC12=$?
cat "$SCRATCH/quoting.out"

ARGC12=$(wc -l < "$ARGV_DUMP" | tr -d ' ')
assert_eq "$ARGC12" "3" "the harness saw exactly three argv entries"
assert_true "argv[1] is --flag" bash -c 'sed -n "1p" "$1" | grep -qx -- "--flag"' _ "$ARGV_DUMP"
assert_true "argv[2] is the quoted value as one entry, unsplit" bash -c 'sed -n "2p" "$1" | grep -qx -- "quoted value"' _ "$ARGV_DUMP"
assert_true "argv[3] is the substituted prompt file path" bash -c 'sed -n "3p" "$1" | grep -q -- "_prompt.md$"' _ "$ARGV_DUMP"
assert_eq "$RC12" "0" "LOOP_HARNESS_CMD quoting run exits 0"

# --------------------------------------------------------------------
# 13. Gate order: simplify, security, review after execute+test; a gate
#     with "no findings" runs no fix stage; the stages the harness saw
#     are exactly plan, execute, simplify, security, review.
# --------------------------------------------------------------------
echo
echo "===== (13) gates run in order and skip fix on no findings ====="
GATE_REVIEW_OUT='no findings\nnothing in the diff is wrong' run_gate_case gates-order --max-iterations 1
assert_eq "$(cat "$SCRATCH/gates-order.rc")" "0" "all-clean gate run exits 0"
assert_eq "$(stages_of gates-order)" "plan execute simplify security review" "stage order is plan, execute, simplify, security, review with no fix"
WT13="$(wt_of gates-order)"
assert_true "LOOP_SUMMARY.md lists the three gates" file_has "$WT13/LOOP_SUMMARY.md" "Gates: simplify security review"
assert_true "LOOP_SUMMARY.md gate log shows 0 findings kept for review" file_has "$WT13/LOOP_SUMMARY.md" "gate review, round 0: 0 finding(s) kept"

# --------------------------------------------------------------------
# 14. Findings filter: a real path:line finding reaches FINDINGS.md and
#     triggers a fix + test; a finding citing a file that does not exist
#     is rejected into .loop-run/REJECTED_FINDINGS.md and never fixed.
#     The second review round (on the fix) says no findings, so the
#     gate converges and the run passes.
# --------------------------------------------------------------------
echo
echo "===== (14) findings filter keeps real paths, rejects invented ones ====="
GATE_REVIEW_OUT='- new_a.txt:1: says "new code" but should say hello\n- ghost/nowhere.py:7: this file was hallucinated' \
  run_gate_case gates-filter --max-iterations 1
# The shim writes the same REVIEW.md every time, so the gate would never
# converge; expect exit 1 with "not converged" -- covered in (16). Here
# check the filter itself on the first round's FINDINGS.md.
STATE14="$SCRATCH/state-gates-filter"
FIRST_FIX_FINDINGS="$(ls "$STATE14"/findings_seen_*.md | head -n1)"
assert_true "a finding citing an existing file reached FINDINGS.md" file_has "$FIRST_FIX_FINDINGS" "new_a.txt:1"
assert_true "a finding citing a missing file was kept out of FINDINGS.md" file_lacks "$FIRST_FIX_FINDINGS" "nowhere.py"
WT14="$(wt_of gates-filter)"
assert_true "the rejected finding was logged with its gate name" file_has "$WT14/.loop-run/REJECTED_FINDINGS.md" "review: - ghost/nowhere.py:7"
assert_true "a fix stage ran after the review gate found something" bash -c 'grep -q "^fix$" "$1"' _ "$STATE14/stages"
assert_true "a test stage ran after the fix (TEST_OUTPUT.txt committed after fix)" bash -c '
  git -C "$1" log --oneline | grep -q "loop: test" && git -C "$1" log --oneline | grep -q "loop: fix"
' _ "$WT14"

# --------------------------------------------------------------------
# 15. Delete guard: a fix stage that deletes a file has its commit
#     reverted, the file is back, and NEEDS_HUMAN.md names it.
# --------------------------------------------------------------------
echo
echo "===== (15) a fix stage that deletes a file is reverted ====="
GATE_REVIEW_OUT='- new_b.txt:1: remove this file' FIX_DELETES=new_b.txt \
  run_gate_case gates-delete --max-iterations 1
WT15="$(wt_of gates-delete)"
assert_true "the deleted file is back after the revert" [ -f "$WT15/new_b.txt" ]
assert_true "the driver logged the revert" file_has "$SCRATCH/gates-delete.out" "reverting that commit"
assert_true "NEEDS_HUMAN.md names the deleted file" file_has "$WT15/NEEDS_HUMAN.md" "new_b.txt"
assert_true "LOOP_SUMMARY.md counts the reverted fix" file_has "$WT15/LOOP_SUMMARY.md" "Fix commits reverted for deleting files: [1-9]"

# --------------------------------------------------------------------
# 16. Two-round cap: a gate that reports the same finding after two fix
#     rounds stops the loop as "not converged", exit 1, even with more
#     iterations allowed.
# --------------------------------------------------------------------
echo
echo "===== (16) a gate that never converges stops after two fix rounds ====="
GATE_REVIEW_OUT='- new_a.txt:1: still wrong' run_gate_case gates-cap --max-iterations 3
assert_eq "$(cat "$SCRATCH/gates-cap.rc")" "1" "non-converging run exits 1"
assert_eq "$(stages_of gates-cap)" "plan execute simplify security review fix review fix review" "exactly two fix rounds, then a third review, then stop"
WT16="$(wt_of gates-cap)"
assert_true "LOOP_SUMMARY.md names the gate that did not converge" file_has "$WT16/LOOP_SUMMARY.md" "Not converged: review"
assert_true "the driver said why it stopped" file_has "$SCRATCH/gates-cap.out" "stopping as not converged"

# --------------------------------------------------------------------
# 17. Missing output: a gate that answers in prose without writing its
#     file is retried once with a write reminder appended; the retry
#     prompt is a different file from the first. A gate that writes
#     nothing twice fails closed: the run cannot pass.
# --------------------------------------------------------------------
echo
echo "===== (17) a gate that writes nothing is nudged once, then fails closed ====="
GATE_REVIEW_OUT='no findings\nclean' REVIEW_SKIP_FIRST=1 run_gate_case gates-nudge --max-iterations 1
assert_eq "$(cat "$SCRATCH/gates-nudge.rc")" "0" "prose-then-file review passes after the nudged retry"
assert_true "the driver logged the write reminder retry" file_has "$SCRATCH/gates-nudge.out" "did not write REVIEW.md; retrying with a write reminder"
WT17="$(wt_of gates-nudge)"
assert_true "the retry prompt carries the reminder line" file_has "$WT17/.loop-run/logs/review_prompt_retry.md" "previous attempt ended without writing REVIEW.md"
assert_eq "$(stages_of gates-nudge)" "plan execute simplify security review review" "review ran twice: the prose attempt and the nudged retry"

GATE_REVIEW_OUT='' run_gate_case gates-noout --max-iterations 1
assert_eq "$(cat "$SCRATCH/gates-noout.rc")" "1" "a gate that never writes its file makes the run fail"
WT17B="$(wt_of gates-noout)"
assert_true "LOOP_SUMMARY.md lists the gate that failed closed" file_has "$WT17B/LOOP_SUMMARY.md" "Gates with no output (failed closed): review"

# --------------------------------------------------------------------
# 18. Per-file split: with LOOP_DIFF_SPLIT_BYTES=1 and two changed
#     files, each gate runs once per file and each run's DIFF.txt holds
#     only that file.
# --------------------------------------------------------------------
echo
echo "===== (18) a large diff runs each gate once per changed file ====="
GATE_REVIEW_OUT='no findings\nclean' LOOP_DIFF_SPLIT_BYTES=1 run_gate_case gates-split --max-iterations 1 --gates review
assert_eq "$(cat "$SCRATCH/gates-split.rc")" "0" "split run exits 0"
assert_eq "$(stages_of gates-split)" "plan execute review review" "review ran once per changed file"
STATE18="$SCRATCH/state-gates-split"
assert_true "first per-file review saw only new_a.txt" bash -c 'file_has "$1/diff_seen_3_review.txt" new_a.txt && file_lacks "$1/diff_seen_3_review.txt" new_b.txt' _ "$STATE18"
assert_true "second per-file review saw only new_b.txt" bash -c 'file_has "$1/diff_seen_4_review.txt" new_b.txt && file_lacks "$1/diff_seen_4_review.txt" new_a.txt' _ "$STATE18"
assert_true "the driver announced the split" file_has "$SCRATCH/gates-split.out" "running once per file"

# --------------------------------------------------------------------
# 19. --gates validation and --gates none.
# --------------------------------------------------------------------
echo
echo "===== (19) --gates rejects unknown names; none skips every gate ====="
GATE_REVIEW_OUT='no findings\nclean' run_gate_case gates-none --max-iterations 1 --gates none
assert_eq "$(cat "$SCRATCH/gates-none.rc")" "0" "--gates none run exits 0"
assert_eq "$(stages_of gates-none)" "plan execute" "--gates none runs no gate and no fix"
DEST19="$SCRATCH/gates-bad/taskrepo"
bash "$RESET_TASK" --dest "$DEST19" >/dev/null
bash "$RUN_LOOP" "$DEST19" "$TASK_PROMPT" --gates simplify,bogus > "$SCRATCH/gates-bad.out" 2>&1
assert_eq "$?" "1" "an unknown gate name exits 1"
assert_true "the unknown gate name is reported" file_has "$SCRATCH/gates-bad.out" "unknown gate 'bogus'"

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
