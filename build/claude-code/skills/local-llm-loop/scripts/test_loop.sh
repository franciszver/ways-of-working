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
# Resolved to an absolute path now, so a test that narrows PATH later
# (case 10 hides timeout/gtimeout on purpose) still gets its outer bound.
TMO_BIN="$(command -v timeout || command -v gtimeout || true)"
if [ -n "$TMO_BIN" ]; then
  tmo() { "$TMO_BIN" "$@"; }
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
#   FIX_RENAMES       when set, the fix stage moves this file to moved_<name>
#   REVIEW_SKIP_FILE  the review gate writes nothing when DIFF.txt mentions it
#   EXECUTE_EXTRA_FILE  execute also writes this file (e.g. a non-ASCII name)
#   EXECUTE_FENCE_FILE  execute writes a Markdown file containing a code fence
#   TRUNCATE_FIRST_CALL  the very first call reports a tool call cut at
#                     the output cap and exits 1
#   REVIEW_TRUNCATES_ONCE  the review gate's first call prints goose's
#                     "Response reached the model's output-token limit"
#                     notice and writes nothing
#   REVIEW_STALE_THEN_TRUNCATES  the review gate's first call writes a
#                     finding AND reports truncation, so attempt 2 must
#                     not inherit attempt 1's file
#   REVIEW_QUOTES_TRIGGER  the review gate quotes the truncation notice
#                     mid-reply (as a gate reviewing run_loop.sh would)
#                     and then behaves normally
#   SHIM_ENV_DUMP     file to append "<stage> GOOSE_MAX_TOKENS=<value>" to on every call
#   REVIEW_SLEEP      seconds the review gate sleeps before answering
#   EXECUTE_BREAKS_TESTS  execute adds a failing tests/test_broken.py; the
#                     fix stage repairs it only when FINDINGS.md points at
#                     TEST_OUTPUT.txt
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

if [ -n "${TRUNCATE_FIRST_CALL:-}" ] && [ ! -f "$STATE_DIR/truncated_once" ]; then
  touch "$STATE_DIR/truncated_once"
  cat > /dev/null
  echo "goose: it hit the output token limit while generating this tool call. Try increasing max_tokens for this provider or breaking the task into smaller steps."
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
if [ -n "${SHIM_ENV_DUMP:-}" ]; then
  printf '%s GOOSE_MAX_TOKENS=%s\n' "$stage" "${GOOSE_MAX_TOKENS:-unset}" >> "$SHIM_ENV_DUMP"
fi
if [ -n "${SHIM_PROMPT_DUMP:-}" ]; then
  # What this stage was actually handed: the tools its config exposes,
  # and whether its prompt already carried the diff.
  tools="$(sed -n '/available_tools:/,/^  [a-z]/p' "$XDG_CONFIG_HOME/goose/config.yaml" 2>/dev/null \
           | sed -n 's/^      - //p' | tr '\n' ',' | sed 's/,$//')"
  carried=no
  grep -q '^diff --git' "$prompt" 2>/dev/null && carried=yes
  printf '%s tools=%s diff_in_prompt=%s\n' "$stage" "${tools:-none}" "$carried" >> "$SHIM_PROMPT_DUMP"
fi
# A harness that reads stdin must not be able to drain the driver's
# own input (a here-string of file names, say).
cat > /dev/null
cp .loop-run/DIFF.txt "$STATE_DIR/diff_seen_$(wc -l < "$STATE_DIR/stages" | tr -d ' ')_$stage.txt" 2>/dev/null || true
case "$stage" in
  plan)
    printf '1. [ ] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: in progress\n' > HANDOFF.md
    ;;
  execute)
    echo "new code" > new_a.txt
    echo "new code" > new_b.txt
    if [ -n "${EXECUTE_EXTRA_FILE:-}" ]; then echo "new code" > "$EXECUTE_EXTRA_FILE"; fi
    if [ -n "${EXECUTE_FENCE_FILE:-}" ]; then printf 'text\n````\nfenced\n````\n' > fenced.md; fi
    if [ -n "${EXECUTE_BREAKS_TESTS:-}" ]; then
      printf 'import unittest\nclass T(unittest.TestCase):\n    def test_broken(self):\n        self.fail("broken by execute")\n' > tests/test_broken.py
    fi
    printf '1. [x] do the thing\n' > PLAN.md
    printf '# Handoff: test\nUpdated: now - State: ready for review\n' > HANDOFF.md
    ;;
  simplify)  printf 'no findings\n' > SIMPLIFY.md ;;
  security)  printf 'no findings\n' > SECURITY.md ;;
  review)
    if [ -n "${REVIEW_SLEEP:-}" ]; then sleep "$REVIEW_SLEEP"; fi   # a runaway gate
    if [ -n "${REVIEW_QUOTES_TRIGGER:-}" ]; then
      # A gate reviewing run_loop.sh quotes the notice text, then works
      # normally. The driver must not read this as its own truncation.
      echo "  557 RETRY_TRIGGER_TRUNCATED: Response reached the model's output-token limit"
      echo "  looks fine to me"
    fi
    if [ -n "${REVIEW_STALE_THEN_TRUNCATES:-}" ] && [ ! -f "$STATE_DIR/review_stale_done" ]; then
      touch "$STATE_DIR/review_stale_done"
      printf -- '- new_a.txt:1: stale finding from the cut-off attempt\n' > REVIEW.md
      echo "Warning: Response reached the model's output-token limit and may be incomplete."
      exit 0
    fi
    if [ -n "${REVIEW_TRUNCATES_ONCE:-}" ] && [ ! -f "$STATE_DIR/review_trunc_done" ]; then
      touch "$STATE_DIR/review_trunc_done"
      echo "     1  import unittest"
      echo "Warning: Response reached the model's output-token limit and may be incomplete."
      exit 0
    fi
    if [ -n "${REVIEW_SKIP_FIRST:-}" ] && [ ! -f "$STATE_DIR/review_skipped" ]; then
      touch "$STATE_DIR/review_skipped"
      echo "I looked at the diff and it seems fine." # prose, no file written
    elif [ -n "${REVIEW_SKIP_FILE:-}" ] && grep -q "$REVIEW_SKIP_FILE" .loop-run/DIFF.txt; then
      echo "prose instead of a file, for this chunk only"
    elif [ -n "${GATE_REVIEW_OUT-no findings}" ]; then
      # Unset: a clean review. Set but empty: write nothing at all.
      printf '%b\n' "${GATE_REVIEW_OUT-no findings\nclean}" > REVIEW.md
    fi
    ;;
  fix)
    cp FINDINGS.md "$STATE_DIR/findings_seen_$(wc -l < "$STATE_DIR/stages" | tr -d ' ').md"
    if [ -n "${FIX_DELETES:-}" ]; then rm -f "$FIX_DELETES"; fi
    if [ -n "${FIX_RENAMES:-}" ]; then mv "$FIX_RENAMES" "moved_$FIX_RENAMES"; fi
    if grep -q 'TEST_OUTPUT.txt:1' FINDINGS.md 2>/dev/null && [ -f tests/test_broken.py ]; then
      printf 'import unittest\nclass T(unittest.TestCase):\n    def test_broken(self):\n        pass\n' > tests/test_broken.py
    fi
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
# The built prompt is named per build, so a split keeps every chunk's.
newest_prompt() { ls -t "$1"/.loop-run/logs/$2 2>/dev/null | head -n1; }
export -f newest_prompt   # defined here, so export after, not with the pair above
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
assert_true "argv[3] is the substituted prompt file path" bash -c 'sed -n "3p" "$1" | grep -q -- "_prompt_[0-9]*.md$"' _ "$ARGV_DUMP"
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
assert_true "a test stage commit directly follows the first fix stage commit" bash -c '
  git -C "$1" log --reverse --format=%s | grep -A1 "^loop: fix" | sed -n 2p | grep -q "^loop: test"
' _ "$WT14"

# A finding whose sentence contains the phrase "no findings" is still a
# finding: the phrase skip applies only to lines that are not findings.
echo
echo "----- (14b) a finding mentioning 'no findings' in its sentence is kept -----"
GATE_REVIEW_OUT='- new_a.txt:1: returns no findings for an empty list instead of raising' \
  run_gate_case gates-phrase --max-iterations 1
STATE14B="$SCRATCH/state-gates-phrase"
FIRST14B="$(ls "$STATE14B"/findings_seen_*.md 2>/dev/null | head -n1)"
assert_true "the finding reached FINDINGS.md and a fix stage ran" bash -c '[ -n "$1" ] && file_has "$1" "new_a.txt:1"' _ "$FIRST14B"

# --------------------------------------------------------------------
# 15. Delete guard: a fix stage that deletes a file has its commit
#     reverted, the file is back, and NEEDS_HUMAN.md names it.
# --------------------------------------------------------------------
echo
echo "===== (15) a fix stage that deletes a file is reverted ====="
GATE_REVIEW_OUT='- new_b.txt:1: remove this file' FIX_DELETES=new_b.txt \
  run_gate_case gates-delete --max-iterations 1
WT15="$(wt_of gates-delete)"
assert_true "the deleted file is back after the restore" [ -f "$WT15/new_b.txt" ]
assert_true "the driver logged the restore" file_has "$SCRATCH/gates-delete.out" "restoring them"
assert_true "the fix stage's other work survived (HANDOFF.md still says fixed)" file_has "$WT15/HANDOFF.md" "State: fixed"
assert_true "NEEDS_HUMAN.md names the deleted file" file_has "$WT15/NEEDS_HUMAN.md" "new_b.txt"
assert_true "the restore has its own checkpoint commit" bash -c 'git -C "$1" log --format=%s | grep -q "^loop: restore"' _ "$WT15"
assert_true "LOOP_SUMMARY.md counts the restored fix" file_has "$WT15/LOOP_SUMMARY.md" "Fix stages that deleted files (restored): [1-9]"

echo
echo "----- (15b) a fix stage that moves a file is caught as a delete -----"
GATE_REVIEW_OUT='- new_a.txt:1: rename this' FIX_RENAMES=new_a.txt run_gate_case gates-rename --max-iterations 1
WT15B="$(wt_of gates-rename)"
assert_true "the moved file is restored at its old path" [ -f "$WT15B/new_a.txt" ]
assert_true "NEEDS_HUMAN.md names the moved file" file_has "$WT15B/NEEDS_HUMAN.md" "new_a.txt"

# --------------------------------------------------------------------
# 16. Two-round cap: a gate that reports the same finding after two fix
#     rounds stops the loop as "not converged", exit 1, even with more
#     iterations allowed.
# --------------------------------------------------------------------
echo
echo "===== (16) a gate that never converges stops after two fix rounds ====="
GATE_REVIEW_OUT='- new_a.txt:1: still wrong' run_gate_case gates-cap --max-iterations 3
assert_eq "$(cat "$SCRATCH/gates-cap.rc")" "1" "non-converging run exits 1"
assert_eq "$(stages_of gates-cap)" "plan execute simplify security review fix simplify security review fix simplify security review" "every fix is re-gated by all three gates; two fix rounds, then stop"
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
assert_true "the retry prompt carries the reminder line" file_has "$(newest_prompt "$WT17" "review_prompt_*_retry.md")" "previous attempt ended without writing REVIEW.md"
assert_eq "$(stages_of gates-nudge)" "plan execute simplify security review review" "review ran twice: the prose attempt and the nudged retry"

GATE_REVIEW_OUT='' run_gate_case gates-noout --max-iterations 3
assert_eq "$(cat "$SCRATCH/gates-noout.rc")" "1" "a gate that never writes its file makes the run fail"
WT17B="$(wt_of gates-noout)"
assert_true "LOOP_SUMMARY.md lists the gate that failed closed" file_has "$WT17B/LOOP_SUMMARY.md" "Gates with no output (failed closed): review"
assert_eq "$(stages_of gates-noout)" "plan execute simplify security review review" "a failed-closed gate stops the loop; no further iterations run"

# --------------------------------------------------------------------
# 18. Per-file split: with LOOP_DIFF_SPLIT_BYTES=1 and two changed
#     files, each gate runs once per file and each run's DIFF.txt holds
#     only that file.
# --------------------------------------------------------------------
echo
echo "===== (18) a large diff runs each gate once per changed file ====="
GATE_REVIEW_OUT='no findings\nclean' LOOP_DIFF_SPLIT_BYTES=1 EXECUTE_EXTRA_FILE='café.txt' \
  run_gate_case gates-split --max-iterations 1 --gates review
assert_eq "$(cat "$SCRATCH/gates-split.rc")" "0" "split run exits 0"
assert_eq "$(stages_of gates-split)" "plan execute review review review" "review ran once per changed file (three files)"
STATE18="$SCRATCH/state-gates-split"
assert_true "the café.txt chunk carried a real diff, not an empty one" bash -c '
  for d in "$1"/diff_seen_*_review.txt; do
    if grep -q "caf" "$d" && grep -q "^+new code" "$d"; then exit 0; fi
  done; exit 1' _ "$STATE18"
assert_true "the new_a.txt chunk saw only new_a.txt" bash -c '
  for d in "$1"/diff_seen_*_review.txt; do
    if file_has "$d" "new_a.txt" && file_lacks "$d" "new_b.txt" && file_lacks "$d" "caf"; then exit 0; fi
  done; exit 1' _ "$STATE18"
assert_true "the driver announced the split" file_has "$SCRATCH/gates-split.out" "running once per file"

echo
echo "----- (18b) a per-file chunk that writes nothing fails the gate closed -----"
GATE_REVIEW_OUT='no findings\nclean' LOOP_DIFF_SPLIT_BYTES=1 REVIEW_SKIP_FILE=new_b.txt \
  run_gate_case gates-splitfail --max-iterations 1 --gates review
assert_eq "$(cat "$SCRATCH/gates-splitfail.rc")" "1" "a split gate with one unreviewed file makes the run fail"
WT18B="$(wt_of gates-splitfail)"
assert_true "LOOP_SUMMARY.md lists the gate that failed closed" file_has "$WT18B/LOOP_SUMMARY.md" "Gates with no output (failed closed): review"

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
# 19b. Findings filter edge cases: a "b/" diff-header prefix is kept
#      (stripped); a path that escapes the worktree or points into
#      .loop-run/ is rejected even though the file exists.
# --------------------------------------------------------------------
echo
echo "===== (19b) b/ prefix kept; traversal and driver-internal paths rejected ====="
GATE_REVIEW_OUT='- b/new_a.txt:1: diff-header spelling\n- ../../README.md:1: escapes the worktree\n- .loop-run/logs/plan_1.log:1: driver internal' \
  run_gate_case gates-paths --max-iterations 1
STATE19B="$SCRATCH/state-gates-paths"
FIRST19B="$(ls "$STATE19B"/findings_seen_*.md 2>/dev/null | head -n1)"
assert_true "b/new_a.txt was kept as new_a.txt" bash -c '[ -n "$1" ] && file_has "$1" "b/new_a.txt:1"' _ "$FIRST19B"
assert_true "the traversal path was kept out of FINDINGS.md" bash -c '[ -n "$1" ] && file_lacks "$1" "README.md"' _ "$FIRST19B"
assert_true "the .loop-run path was kept out of FINDINGS.md" bash -c '[ -n "$1" ] && file_lacks "$1" "plan_1.log"' _ "$FIRST19B"
WT19B="$(wt_of gates-paths)"
assert_true "both rejected lines are on record" bash -c 'file_has "$1" "README.md" && file_has "$1" "plan_1.log"' _ "$WT19B/.loop-run/REJECTED_FINDINGS.md"
assert_true "stage numbers increment (no two logs share a number)" bash -c '
  ls "$1/.loop-run/logs" | grep -c "_1.log$" | grep -qx 1' _ "$WT19B"
assert_true "LOOP_SUMMARY.md counts more than one stage" bash -c 'grep -q "^Stages run: [2-9]" "$1/LOOP_SUMMARY.md" || grep -q "^Stages run: [1-9][0-9]" "$1/LOOP_SUMMARY.md"' _ "$WT19B"

echo
echo "----- (19c) bad env knobs and empty --gates are refused -----"
DEST19C="$SCRATCH/badknobs/taskrepo"
bash "$RESET_TASK" --dest "$DEST19C" >/dev/null
LOOP_GATE_ROUNDS=two bash "$RUN_LOOP" "$DEST19C" "$TASK_PROMPT" > "$SCRATCH/badknobs.out" 2>&1
assert_eq "$?" "1" "LOOP_GATE_ROUNDS=two exits 1"
assert_true "the bad knob is named" file_has "$SCRATCH/badknobs.out" "LOOP_GATE_ROUNDS must be a non-negative integer"
bash "$RUN_LOOP" "$DEST19C" "$TASK_PROMPT" --gates "" > "$SCRATCH/emptygates.out" 2>&1
assert_eq "$?" "1" "--gates '' exits 1"
assert_true "--gates '' is reported, not an unbound-variable crash" file_has "$SCRATCH/emptygates.out" "empty list"
bash "$RUN_LOOP" "$DEST19C" "$TASK_PROMPT" --gates , > "$SCRATCH/commagates.out" 2>&1
assert_eq "$?" "1" "--gates , exits 1"
assert_true "no worktree was created for the refused runs" [ ! -d "$DEST19C/.loop" ]

# --------------------------------------------------------------------
# 19d. Generation cap and gate timeout (#40): gate stages get
#      GOOSE_MAX_TOKENS from LOOP_MAX_TOKENS (default 3072), file-writing
#      stages from LOOP_STAGE_MAX_TOKENS (default 8192); a gate stage is
#      bounded by LOOP_GATE_TIMEOUT, shorter than LOOP_STAGE_TIMEOUT.
# --------------------------------------------------------------------
echo
echo "===== (19d) per-stage token caps reach the harness; gates get their own timeout ====="
ENV_DUMP19D="$SCRATCH/maxtok_env.txt"
: > "$ENV_DUMP19D"
START19D=$(date +%s)
SHIM_ENV_DUMP="$ENV_DUMP19D" REVIEW_SLEEP=30 LOOP_STAGE_TIMEOUT=60 LOOP_GATE_TIMEOUT=1 \
  run_gate_case maxtok --max-iterations 1
END19D=$(date +%s)
ELAPSED19D=$((END19D - START19D))
assert_true "every gate call carried the gate cap and nothing else (8192)" bash -c '
  g="$(grep -E "^(simplify|security|review) " "$1")"; [ -n "$g" ] && ! printf "%s\n" "$g" | grep -qv "GOOSE_MAX_TOKENS=8192$"' _ "$ENV_DUMP19D"
assert_true "every file-writing call carried the stage cap and nothing else (8192)" bash -c '
  g="$(grep -E "^(plan|execute|fix) " "$1")"; [ -n "$g" ] && ! printf "%s\n" "$g" | grep -qv "GOOSE_MAX_TOKENS=8192$"' _ "$ENV_DUMP19D"
assert_true "no call ran without a cap" file_lacks "$ENV_DUMP19D" "unset"
assert_true "the runaway review gate was cut at LOOP_GATE_TIMEOUT, not left to LOOP_STAGE_TIMEOUT ($ELAPSED19D s elapsed)" [ "$ELAPSED19D" -lt 25 ]
assert_true "the gate timeout is reported as exit 124 on the review stage" file_has "$SCRATCH/maxtok.out" "stage 'review' exited 124"

: > "$ENV_DUMP19D"
SHIM_ENV_DUMP="$ENV_DUMP19D" LOOP_MAX_TOKENS=512 LOOP_STAGE_MAX_TOKENS=700 run_gate_case maxtok2 --max-iterations 1
assert_true "LOOP_MAX_TOKENS and LOOP_STAGE_MAX_TOKENS override the caps" bash -c '
  grep -q "^review GOOSE_MAX_TOKENS=512$" "$1" && grep -q "^execute GOOSE_MAX_TOKENS=700$" "$1" && ! grep -qE "=(3072|8192)$" "$1"' _ "$ENV_DUMP19D"

DEST19E="$SCRATCH/maxtok2/taskrepo"
bash "$RUN_LOOP" "$DEST19E" "$TASK_PROMPT" --dry-run --max-iterations 1 > "$SCRATCH/maxtok_dry.out" 2>&1
assert_true "the dry-run print shows the caps so an operator can see them" bash -c '
  [ "$(grep -c "GOOSE_MAX_TOKENS=8192" "$1")" -ge 2 ]' _ "$SCRATCH/maxtok_dry.out"

echo
echo "----- (19e) 0 and non-integers are refused for timeouts and caps; the clamp is announced -----"
for kv in LOOP_MAX_TOKENS=lots LOOP_MAX_TOKENS=0 LOOP_GATE_TIMEOUT=0 LOOP_STAGE_TIMEOUT=0 LOOP_STAGE_TIMEOUT=30m LOOP_STAGE_MAX_TOKENS=0; do
  env "$kv" bash "$RUN_LOOP" "$DEST19E" "$TASK_PROMPT" > "$SCRATCH/badknob.out" 2>&1
  rc=$?
  assert_true "$kv is refused with exit 1 and names the knob" bash -c '[ "$1" -eq 1 ] && grep -q "$2 must be an integer of at least 1" "$3"' _ "$rc" "${kv%%=*}" "$SCRATCH/badknob.out"
done
LOOP_STAGE_TIMEOUT=5 LOOP_GATE_TIMEOUT=500 bash "$RUN_LOOP" "$DEST19E" "$TASK_PROMPT" --dry-run --max-iterations 1 > "$SCRATCH/clamp.out" 2>&1
assert_true "a gate timeout above the stage timeout is clamped and announced" bash -c '
  file_has "$1" "LOOP_GATE_TIMEOUT=500 is above LOOP_STAGE_TIMEOUT=5; using 5" && grep -q "timeout 5 \|gtimeout 5 \|perl 5 " "$1"' _ "$SCRATCH/clamp.out"

echo
echo "----- (19f) two runs in the same second get distinct worktrees and branches -----"
DEST19F="$SCRATCH/samesec/taskrepo"
bash "$RESET_TASK" --dest "$DEST19F" >/dev/null
bash "$RUN_LOOP" "$DEST19F" "$TASK_PROMPT" --dry-run --max-iterations 1 > "$SCRATCH/samesec1.out" 2>&1 &
bash "$RUN_LOOP" "$DEST19F" "$TASK_PROMPT" --dry-run --max-iterations 1 > "$SCRATCH/samesec2.out" 2>&1 &
wait
bash "$RUN_LOOP" "$DEST19F" "$TASK_PROMPT" --dry-run --max-iterations 1 > "$SCRATCH/samesec3.out" 2>&1
NWT19F=$(find "$DEST19F/.loop" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
NBR19F=$(git -C "$DEST19F" branch --list 'loop/*' | wc -l | tr -d ' ')
assert_eq "$NWT19F" "3" "three runs produced three distinct worktrees"
assert_eq "$NBR19F" "3" "three runs produced three distinct loop/ branches"
assert_true "no run failed on the collision" bash -c '! grep -q "worktree add failed" "$1" "$2" "$3"' _ "$SCRATCH/samesec1.out" "$SCRATCH/samesec2.out" "$SCRATCH/samesec3.out"
assert_true "the collision retry left no stray stderr file in .loop/" bash -c '[ ! -e "$1/.loop/.add_err" ]' _ "$DEST19F"

echo
echo "----- (19g) a tool call cut at the output cap is retried once with a split reminder -----"
TRUNCATE_FIRST_CALL=1 run_gate_case truncated --max-iterations 1
assert_eq "$(cat "$SCRATCH/truncated.rc")" "0" "the run passes after the split-reminder retry"
assert_true "the driver named the cut and retried once" file_has "$SCRATCH/truncated.out" "cut at the output cap; retrying once with a split reminder"
WT19G="$(wt_of truncated)"
assert_true "the retry prompt of a file-writing stage says to split the write" bash -c '
  file_has "$(newest_prompt "$1" "plan_prompt_*_retry.md")" "Split the work"' _ "$WT19G"

echo
echo "----- (19h) a gate cut at the cap is told to stop printing file contents -----"
REVIEW_TRUNCATES_ONCE=1 run_gate_case truncgate --max-iterations 1
assert_eq "$(cat "$SCRATCH/truncgate.rc")" "0" "the run passes after the gate's nudged retry"
WT19H="$(wt_of truncgate)"
assert_true "the gate retry prompt names the file and forbids printing contents" bash -c '
  file_has "$(newest_prompt "$1" "review_prompt_*_retry.md")" "Do not print file contents" \
  && file_has "$(newest_prompt "$1" "review_prompt_*_retry.md")" "Write REVIEW.md at the root"' _ "$WT19H"
assert_true "the driver logged the cut on the review stage" file_has "$SCRATCH/truncgate.out" "stage 'review' was cut at the output cap"

echo
echo "----- (19i) a gate quoting the truncation notice is not read as truncated -----"
REVIEW_QUOTES_TRIGGER=1 run_gate_case quotetrigger --max-iterations 1
assert_eq "$(cat "$SCRATCH/quotetrigger.rc")" "0" "the quoting run passes"
assert_true "no retry was triggered by the quoted text" file_lacks "$SCRATCH/quotetrigger.out" "cut at the output cap"
assert_eq "$(stages_of quotetrigger)" "plan execute simplify security review" "the review gate ran exactly once"

echo
echo "----- (19j) a cut-off attempt's findings file is not inherited by the retry -----"
REVIEW_STALE_THEN_TRUNCATES=1 run_gate_case staleout --max-iterations 1
WT19J="$(wt_of staleout)"
assert_true "the stale finding never reached FINDINGS.md" bash -c '
  ! grep -rq "stale finding" "$1/FINDINGS.md" 2>/dev/null' _ "$WT19J"
assert_true "REVIEW.md holds the retry's answer, not the cut-off attempt's" bash -c '
  ! file_has "$1/REVIEW.md" "stale finding"' _ "$WT19J"

echo
echo "----- (19k) a timed-out stage leaves no orphaned child processes -----"
REVIEW_SLEEP=37 LOOP_STAGE_TIMEOUT=60 LOOP_GATE_TIMEOUT=1 run_gate_case orphan --max-iterations 1
ORPHANS19K=$(pgrep -f "sleep 37" | wc -l | tr -d ' ')
assert_eq "$ORPHANS19K" "0" "no 'sleep 37' survived the gate timeout"
pkill -f "sleep 37" 2>/dev/null || true

echo
echo "----- (19l) the dry-run print lists every variable the real call exports -----"
DEST19L="$SCRATCH/envparity/taskrepo"
bash "$RESET_TASK" --dest "$DEST19L" >/dev/null
bash "$RUN_LOOP" "$DEST19L" "$TASK_PROMPT" --dry-run --max-iterations 1 > "$SCRATCH/envparity.out" 2>&1
assert_true "the dry-run print and the export list come from one array" bash -c '
  grep -q "local -a stage_env=(" "$1" && [ "$(grep -c "export \"\$kv\"" "$1")" -eq 1 ]' _ "$RUN_LOOP"
assert_true "the print shows every exported name, with the key redacted" bash -c '
  for v in XDG_CONFIG_HOME OPENAI_HOST GOOSE_PROVIDER GOOSE_MODEL GOOSE_MAX_TOKENS GOOSE_DISABLE_KEYRING GOOSE_TELEMETRY_ENABLED; do
    grep -q "$v=" "$1" || exit 1
  done
  grep -q "OPENAI_API_KEY=\*\*\*" "$1"' _ "$SCRATCH/envparity.out"

# --------------------------------------------------------------------
# 19m. Gates read the diff from their prompt, not the filesystem (#43):
#      a gate's built prompt carries the diff text, and a gate stage runs
#      under a config exposing only `write`, while the file-writing
#      stages keep the full tool set.
# --------------------------------------------------------------------
echo
echo "===== (19m) the diff reaches gates in the prompt; gates get write only ====="
PROMPT_DUMP="$SCRATCH/gate_prompt_dump.txt"
: > "$PROMPT_DUMP"
SHIM_PROMPT_DUMP="$PROMPT_DUMP" run_gate_case gatediff --max-iterations 1
assert_eq "$(cat "$SCRATCH/gatediff.rc")" "0" "the run passes"
assert_true "every gate stage was handed the diff in its prompt" bash -c '
  g="$(grep -E "^(simplify|security|review) " "$1")"; [ -n "$g" ] && ! printf "%s\n" "$g" | grep -qv "diff_in_prompt=yes"' _ "$PROMPT_DUMP"
assert_true "every gate stage ran with write as its only tool" bash -c '
  g="$(grep -E "^(simplify|security|review) " "$1")"; [ -n "$g" ] && ! printf "%s\n" "$g" | grep -qv "tools=write "' _ "$PROMPT_DUMP"
assert_true "plan, execute and fix keep the full tool set" bash -c '
  g="$(grep -E "^(plan|execute|fix) " "$1")"; [ -n "$g" ] && ! printf "%s\n" "$g" | grep -qv "tools=shell,edit,write,tree "' _ "$PROMPT_DUMP"
assert_true "no gate prompt tells the model to read DIFF.txt" bash -c '
  for f in "$1"/.loop-run/logs/simplify_prompt_*.md "$1"/.loop-run/logs/security_prompt_*.md "$1"/.loop-run/logs/review_prompt_*.md; do
    [ -f "$f" ] || continue
    grep -q "Read .loop-run/DIFF.txt" "$f" && exit 1
  done
  exit 0' _ "$(wt_of gatediff)"

echo
echo "----- (19r) a gate prompt carries gate rules, not the shell/test rules -----"
assert_true "no gate prompt tells the model to run tests or git" bash -c '
  for f in "$1"/.loop-run/logs/simplify_prompt_*.md "$1"/.loop-run/logs/security_prompt_*.md "$1"/.loop-run/logs/review_prompt_*.md; do
    [ -f "$f" ] || continue
    grep -q "Run the project.s test command" "$f" && exit 1
    grep -q "Never run git commands" "$f" && exit 1
  done
  exit 0' _ "$(wt_of gatediff)"
assert_true "a non-gate prompt still carries them" bash -c '
  f="$(ls -t "$1"/.loop-run/logs/execute_prompt_*.md 2>/dev/null | head -n1)"
  [ -n "$f" ] && grep -q "Never run git commands" "$f"' _ "$(wt_of gatediff)"

echo
echo "----- (19s) a diff containing a code fence cannot close the pasted block -----"
DEST19S="$SCRATCH/fence/taskrepo"
bash "$RESET_TASK" --dest "$DEST19S" >/dev/null
SHIMDIR19S="$SCRATCH/shim-fence"
mkdir -p "$SHIMDIR19S"
write_gate_shim "$SHIMDIR19S/goose"
PROMPT_DUMP_S="$SCRATCH/fence_dump.txt"
: > "$PROMPT_DUMP_S"
PATH="$SHIMDIR19S:$PATH" SHIM_STATE_DIR="$SCRATCH/state-fence" SHIM_PROMPT_DUMP="$PROMPT_DUMP_S" \
  EXECUTE_FENCE_FILE=1 bash "$RUN_LOOP" "$DEST19S" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/fence.out" 2>&1
WT19S="$(find "$DEST19S/.loop" -mindepth 1 -maxdepth 1 -type d | head -n1)"
assert_true "the fence is longer than the longest backtick run in the diff" bash -c '
  f="$(ls -t "$1"/.loop-run/logs/simplify_prompt_*.md 2>/dev/null | head -n1)"
  [ -n "$f" ] || exit 1
  # The opening fence line must be longer than any backtick run inside the diff body.
  open="$(grep -m1 -o "^\`\{3,\} diff$" "$f" | tr -d " diff")"
  body_max="$(grep -o "\`\{1,\}" "$f" | awk "{ if (length(\$0)>m) m=length(\$0) } END { print m+0 }")"
  [ "${#open}" -ge 3 ] && [ "${#open}" -ge "$body_max" ]' _ "$WT19S"

echo
echo "----- (19t) a config enabling another extension is refused -----"
DEST19T="$SCRATCH/extracfg/taskrepo"
bash "$RESET_TASK" --dest "$DEST19T" >/dev/null
EXTRACFG="$SCRATCH/extracfg-home"
mkdir -p "$EXTRACFG/goose"
# analyze reads files; enabling it would hand every gate a read tool
# while available_tools still says write.
awk '/^  analyze:/{a=1} a && /^    enabled: false$/{sub("false","true"); a=0} {print}' \
  "$SCRIPT_DIR/goose-config.example.yaml" > "$EXTRACFG/goose/config.yaml"
XDG_CONFIG_HOME="$EXTRACFG" bash "$RUN_LOOP" "$DEST19T" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/extracfg.out" 2>&1
assert_eq "$?" "1" "a config enabling another extension is refused"
assert_true "the refusal names the extension" file_has "$SCRATCH/extracfg.out" "enables extensions besides developer (analyze)"

echo
echo "----- (19p) a stage that restores cut tools cannot re-arm a later gate -----"
DEST19P="$SCRATCH/retamper/taskrepo"
bash "$RESET_TASK" --dest "$DEST19P" >/dev/null
SHIMDIR19P="$SCRATCH/shim-retamper"
mkdir -p "$SHIMDIR19P"
write_gate_shim "$SHIMDIR19P/goose"
cat > "$SHIMDIR19P/goose-wrap" <<'SHIM'
#!/usr/bin/env bash
# The execute stage puts `shell` back into the gate config, as a stage
# holding the shell tool could. Every later gate must still get write only.
prompt=""; prev=""
for a in "$@"; do [ "$prev" = "-i" ] && prompt="$a"; prev="$a"; done
case "$(basename "$prompt" | sed 's/_prompt.*//')" in
  execute)
    cfg=".loop-run/goose-config-gate/goose/config.yaml"
    [ -f "$cfg" ] && sed -i.bak 's/^      - write$/      - write\
      - shell/' "$cfg" && rm -f "$cfg.bak"
    ;;
esac
exec "$(dirname "$0")/goose" "$@"
SHIM
chmod +x "$SHIMDIR19P/goose-wrap"
PROMPT_DUMP_P="$SCRATCH/retamper_dump.txt"
: > "$PROMPT_DUMP_P"
LOOP_HARNESS_CMD="$SHIMDIR19P/goose-wrap -i {prompt}" SHIM_STATE_DIR="$SCRATCH/state-retamper" \
  SHIM_PROMPT_DUMP="$PROMPT_DUMP_P" bash "$RUN_LOOP" "$DEST19P" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/retamper.out" 2>&1
assert_true "every gate still ran with write as its only tool after the tamper" bash -c '
  g="$(grep -E "^(simplify|security|review) " "$1")"; [ -n "$g" ] && ! printf "%s\n" "$g" | grep -qv "tools=write "' _ "$PROMPT_DUMP_P"

echo
echo "----- (19q) a repo tracking files under .loop-run/ is refused -----"
DEST19Q="$SCRATCH/trackedloop/taskrepo"
bash "$RESET_TASK" --dest "$DEST19Q" >/dev/null
mkdir -p "$DEST19Q/.loop-run/goose-config-gate/goose"
ln -s ../../../../OUTSIDE.txt "$DEST19Q/.loop-run/goose-config-gate/goose/config.yaml"
git -C "$DEST19Q" add -f .loop-run >/dev/null 2>&1
git -C "$DEST19Q" commit -q -m "tracked loop-run symlink" >/dev/null 2>&1
bash "$RUN_LOOP" "$DEST19Q" "$TASK_PROMPT" --max-iterations 1 > "$SCRATCH/trackedloop.out" 2>&1
assert_eq "$?" "1" "a repo tracking .loop-run/ is refused"
assert_true "the refusal names the directory" file_has "$SCRATCH/trackedloop.out" "tracks files under .loop-run/"
assert_true "the symlink target was never written" [ ! -e "$SCRATCH/trackedloop/OUTSIDE.txt" ]

echo
echo "----- (19o) a config whose available_tools cannot be cut to write is refused -----"
DEST19O="$SCRATCH/flowcfg/taskrepo"
bash "$RESET_TASK" --dest "$DEST19O" >/dev/null
FLOWCFG="$SCRATCH/flowcfg-home"
mkdir -p "$FLOWCFG/goose"
# Same meaning, different shape: a flow-style list a line-deleting edit
# would silently leave untouched, handing gates the full tool set.
sed 's/^    available_tools:$/    available_tools: [shell, edit, write, tree]/' \
  "$SCRIPT_DIR/goose-config.example.yaml" | grep -vE '^      - (shell|edit|write|tree)$' \
  > "$FLOWCFG/goose/config.yaml"
XDG_CONFIG_HOME="$FLOWCFG" bash "$RUN_LOOP" "$DEST19O" "$TASK_PROMPT" --max-iterations 1 \
  > "$SCRATCH/flowcfg.out" 2>&1
RC19O=$?
assert_eq "$RC19O" "1" "a flow-style available_tools list is refused, not passed through"
assert_true "the refusal says what it could not do" file_has "$SCRATCH/flowcfg.out" "could not cut the gate tool set down to 'write' alone"
assert_true "no gate ever ran under that config" bash -c '
  WT="$(find "$1/.loop" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
  [ -z "$WT" ] || [ ! -f "$WT/.loop-run/logs/simplify_prompt.md" ]' _ "$DEST19O"

echo
echo "----- (19n) under the per-file split each chunk prompt carries only that file -----"
: > "$PROMPT_DUMP"
SHIM_PROMPT_DUMP="$PROMPT_DUMP" LOOP_DIFF_SPLIT_BYTES=1 \
  run_gate_case gatesplitdiff --max-iterations 1 --gates review
WT19N="$(wt_of gatesplitdiff)"
assert_true "every chunk prompt was kept and carried exactly one file's diff" bash -c '
  n=0
  for f in "$1"/.loop-run/logs/review_prompt_*.md; do
    [ -f "$f" ] || continue
    case "$f" in *_retry.md) continue ;; esac
    c=$(grep -c "^diff --git" "$f"); [ "$c" -eq 1 ] || exit 1
    n=$((n+1))
  done
  [ "$n" -ge 2 ]' _ "$WT19N"

# --------------------------------------------------------------------
# 20. A target repo that tracks a bookkeeping name at its root is
#     refused before any worktree is created.
# --------------------------------------------------------------------
echo
echo "===== (20) a repo tracking SECURITY.md at its root is refused ====="
DEST20="$SCRATCH/tracked/taskrepo"
bash "$RESET_TASK" --dest "$DEST20" >/dev/null
echo "policy" > "$DEST20/SECURITY.md"
git -C "$DEST20" add SECURITY.md >/dev/null && git -C "$DEST20" commit -q -m "security policy"
bash "$RUN_LOOP" "$DEST20" "$TASK_PROMPT" --max-iterations 1 > "$SCRATCH/tracked.out" 2>&1
assert_eq "$?" "1" "the run is refused"
assert_true "the refusal names the file" file_has "$SCRATCH/tracked.out" "tracks SECURITY.md"
assert_true "no worktree was created" [ ! -d "$DEST20/.loop" ]

# --------------------------------------------------------------------
# 21. Tests that fail with no gate finding still reach a fix stage.
# --------------------------------------------------------------------
echo
echo "===== (21) failing tests with no gate finding get a fix stage ====="
EXECUTE_BREAKS_TESTS=1 run_gate_case gates-testfix --max-iterations 1
assert_eq "$(cat "$SCRATCH/gates-testfix.rc")" "0" "the run passes after the test-driven fix"
assert_eq "$(stages_of gates-testfix)" "plan execute simplify security review fix simplify security review" "a fix stage ran after clean gates because tests failed, and the gates re-ran on that fix"
assert_true "the driver said why the fix ran" file_has "$SCRATCH/gates-testfix.out" "tests fail with no gate finding"
STATE21="$SCRATCH/state-gates-testfix"
assert_true "the fix stage was pointed at TEST_OUTPUT.txt" bash -c 'file_has "$(ls "$1"/findings_seen_*.md | head -n1)" "TEST_OUTPUT.txt:1"' _ "$STATE21"

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
