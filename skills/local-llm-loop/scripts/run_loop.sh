#!/usr/bin/env bash
# Unattended agent loop driver for a local-LLM-backed Goose agent.
#
# Usage:
#   run_loop.sh <repo_path> <plan_file> [--max-iterations N] [--test-cmd "..."] [--dry-run]
#
# Runs a plan through a fresh-context Goose stage sequence
# (plan -> execute -> test -> review -> fix -> test, looping
# execute..test until the plan has no unchecked steps and tests pass, or
# --max-iterations is reached) in a disposable git worktree, committing
# after every stage. The endpoint is passed as explicit environment
# variables on the goose command itself, never relying on a config file
# for OPENAI_HOST/OPENAI_API_KEY/GOOSE_MODEL, so a stale config can't
# silently override it.
#
# --dry-run skips only the actual `goose run` calls (printed instead)
# and the per-stage git commits (printed instead); the worktree,
# branch, and prompt files are still created for real, and the
# mechanical test stage still runs for real, so the harness plumbing
# can be verified without a model.

set -u
set -o pipefail

usage() {
  cat <<'EOF'
Usage: run_loop.sh <repo_path> <plan_file> [--max-iterations N] [--test-cmd "..."] [--dry-run]

  <repo_path>          Path to an existing git repo to run the loop against.
  <plan_file>          Path to a file describing the task to plan and execute.
  --max-iterations N   Cap on execute/test/review/fix/test cycles (default 3).
  --test-cmd "..."     Mechanical test command to run in the worktree.
                        Default: `python3 -m unittest discover -s tests -t .`
                        if tests/ exists, else `make test` if the Makefile
                        has a test target, else the test stage is skipped
                        with a warning.
  --dry-run            Print every command instead of invoking goose or
                        committing per stage; still creates the worktree
                        and runs the real mechanical test command.

Environment (see env.example):
  OPENAI_HOST          Base URL of an OpenAI-compatible endpoint. Required.
  OPENAI_API_KEY       API key sent to that endpoint. Required.
  GOOSE_MODEL          Model name to request. Required.
  XDG_CONFIG_HOME      Optional. A directory containing goose/config.yaml
                        (see goose-config.example.yaml) to seed each run's
                        isolated Goose config from. If unset, the bundled
                        goose-config.example.yaml is used directly.
  LOOP_STAGE_TIMEOUT   Optional. Per-stage timeout in seconds (default 1800).
EOF
}

# --------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------
DRY_RUN=false
MAX_ITERATIONS=3
TEST_CMD_OVERRIDE=""
POSITIONAL=()

while [ $# -gt 0 ]; do
  case "$1" in
    --max-iterations)
      if [ $# -lt 2 ]; then
        echo "run_loop.sh: --max-iterations requires a value" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --test-cmd)
      if [ $# -lt 2 ]; then
        echo "run_loop.sh: --test-cmd requires a value" >&2
        exit 1
      fi
      TEST_CMD_OVERRIDE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do POSITIONAL+=("$1"); shift; done
      ;;
    -*)
      echo "run_loop.sh: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

REPO_PATH="${POSITIONAL[0]:-}"
PLAN_FILE="${POSITIONAL[1]:-}"

if [ -z "$REPO_PATH" ] || [ -z "$PLAN_FILE" ]; then
  usage >&2
  exit 1
fi

case "$MAX_ITERATIONS" in
  ''|*[!0-9]*)
    echo "run_loop.sh: --max-iterations must be a positive integer, got '$MAX_ITERATIONS'" >&2
    exit 1
    ;;
esac

# --------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------
REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)" || {
  echo "run_loop.sh: repo path does not exist: ${POSITIONAL[0]:-}" >&2
  exit 1
}

if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "run_loop.sh: not a git repo: $REPO_PATH" >&2
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "run_loop.sh: plan file not found: $PLAN_FILE" >&2
  exit 1
fi
PLAN_FILE_ABS="$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")"

# --------------------------------------------------------------------
# Endpoint settings: env vars only, no repo-specific fallback config.
# --------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
BUNDLED_GOOSE_CONFIG="$SCRIPT_DIR/goose-config.example.yaml"

MISSING=()
[ -z "${OPENAI_HOST:-}" ] && MISSING+=("OPENAI_HOST")
[ -z "${OPENAI_API_KEY:-}" ] && MISSING+=("OPENAI_API_KEY")
[ -z "${GOOSE_MODEL:-}" ] && MISSING+=("GOOSE_MODEL")
if [ "${#MISSING[@]}" -gt 0 ] && ! $DRY_RUN; then
  echo "run_loop.sh: missing required environment variable(s): ${MISSING[*]} (see env.example)" >&2
  exit 1
fi
OPENAI_HOST="${OPENAI_HOST:-http://127.0.0.1:8080}"
OPENAI_API_KEY="${OPENAI_API_KEY:-sk-local}"
GOOSE_MODEL="${GOOSE_MODEL:-dry-run-placeholder}"

STAGE_TIMEOUT="${LOOP_STAGE_TIMEOUT:-1800}"

# --------------------------------------------------------------------
# Worktree setup (always real, even under --dry-run, so plumbing checks
# have something to inspect).
# --------------------------------------------------------------------
TS="$(date +%Y%m%d-%H%M%S)"
BRANCH="loop/$TS"
WORKTREE="$REPO_PATH/.loop/$TS"
mkdir -p "$REPO_PATH/.loop"

echo "run_loop.sh: creating worktree $WORKTREE on branch $BRANCH"
if ! git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE" >/dev/null; then
  echo "run_loop.sh: git worktree add failed" >&2
  exit 1
fi

BASE_COMMIT="$(git -C "$WORKTREE" rev-parse HEAD)"
LOG_DIR="$WORKTREE/.loop-run/logs"
GOOSE_CONFIG_DIR="$WORKTREE/.loop-run/goose-config"
mkdir -p "$LOG_DIR" "$GOOSE_CONFIG_DIR/goose"

# Seed this run's isolated Goose config: from $XDG_CONFIG_HOME/goose/config.yaml
# if the caller pointed one at us, else from the bundled hardened example.
if [ -n "${XDG_CONFIG_HOME:-}" ] && [ -f "$XDG_CONFIG_HOME/goose/config.yaml" ]; then
  cp "$XDG_CONFIG_HOME/goose/config.yaml" "$GOOSE_CONFIG_DIR/goose/config.yaml"
else
  cp "$BUNDLED_GOOSE_CONFIG" "$GOOSE_CONFIG_DIR/goose/config.yaml"
fi

cp "$PLAN_FILE_ABS" "$WORKTREE/PLAN_INPUT.md"

# .loop-run/ holds raw goose stdout/stderr, which can echo back
# whatever ambient debug/verbose env vars cause a client library to
# print (e.g. request headers) -- never let it enter the worktree's
# committed history, since OPENAI_API_KEY is passed to goose only via
# the environment specifically to keep it out of committed files.
if ! grep -qxF '.loop-run/' "$WORKTREE/.gitignore" 2>/dev/null; then
  printf '.loop-run/\n' >> "$WORKTREE/.gitignore"
fi
(cd "$WORKTREE" && git add .gitignore >/dev/null 2>&1) || true

# --------------------------------------------------------------------
# Mechanical test command
# --------------------------------------------------------------------
if [ -n "$TEST_CMD_OVERRIDE" ]; then
  TEST_CMD="$TEST_CMD_OVERRIDE"
elif [ -d "$WORKTREE/tests" ]; then
  TEST_CMD="python3 -m unittest discover -s tests -t ."
elif [ -f "$WORKTREE/Makefile" ] && grep -qE '^test:' "$WORKTREE/Makefile"; then
  TEST_CMD="make test"
else
  TEST_CMD=""
  echo "run_loop.sh: WARNING no tests/ dir, no Makefile test target, and no --test-cmd given; the test stage will be skipped" >&2
fi

# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------
STEP_N=0
STAGES_RUN=()

next_step_n() {
  STEP_N=$((STEP_N + 1))
  echo "$STEP_N"
}

plan_has_unchecked() {
  # Fail closed: no PLAN.md yet (goose crashed, never ran, or wrote
  # nothing) counts as "not done", never as "nothing left to do".
  if [ ! -f "$WORKTREE/PLAN.md" ]; then
    return 0
  fi
  grep -q '\[ \]' "$WORKTREE/PLAN.md"
}

commit_stage() {
  local name="$1" n="$2"
  if $DRY_RUN; then
    echo "[dry-run] would run: (cd $WORKTREE && git add -A && git commit --allow-empty -m \"loop: $name $n\")"
    return 0
  fi
  (cd "$WORKTREE" && git add -A && git commit --allow-empty -q -m "loop: $name $n")
}

invoke_goose() {
  local prompt_file="$1" log_file="$2"
  if $DRY_RUN; then
    echo "[dry-run] would run: (cd $WORKTREE && env XDG_CONFIG_HOME=$GOOSE_CONFIG_DIR OPENAI_HOST=$OPENAI_HOST OPENAI_API_KEY=*** GOOSE_PROVIDER=openai GOOSE_MODEL=$GOOSE_MODEL GOOSE_DISABLE_KEYRING=1 GOOSE_TELEMETRY_ENABLED=false timeout $STAGE_TIMEOUT goose run --no-session -i $prompt_file) > $log_file 2>&1"
    : > "$log_file"
    return 0
  fi
  (
    cd "$WORKTREE" || exit 99
    env XDG_CONFIG_HOME="$GOOSE_CONFIG_DIR" \
        OPENAI_HOST="$OPENAI_HOST" OPENAI_API_KEY="$OPENAI_API_KEY" \
        GOOSE_PROVIDER=openai GOOSE_MODEL="$GOOSE_MODEL" GOOSE_DISABLE_KEYRING=1 \
        GOOSE_TELEMETRY_ENABLED=false \
        timeout "$STAGE_TIMEOUT" goose run --no-session -i "$prompt_file"
  ) > "$log_file" 2>&1
  return $?
}

# Runs one fresh-context goose stage, retrying once on a format
# rejection (HTTP 500 / "does not match the expected") and aborting the
# whole loop on a 404 ("Resource not found"). Returns 0 on success, 3
# to signal "abort: endpoint misconfigured".
run_model_stage() {
  local name="$1" prompt_file="$2"
  local n log_file
  n="$(next_step_n)"
  STAGES_RUN+=("$name")
  log_file="$LOG_DIR/${name}_${n}.log"

  local goose_rc
  invoke_goose "$prompt_file" "$log_file"
  goose_rc=$?

  if grep -q 'Resource not found' "$log_file" 2>/dev/null; then
    return 3
  fi

  if grep -qE 'HTTP 500|does not match the expected' "$log_file" 2>/dev/null; then
    echo "run_loop.sh: stage '$name' hit a format rejection; retrying once" >&2
    n="$(next_step_n)"
    log_file="$LOG_DIR/${name}_${n}_retry.log"
    invoke_goose "$prompt_file" "$log_file"
    goose_rc=$?
    if grep -q 'Resource not found' "$log_file" 2>/dev/null; then
      return 3
    fi
    if grep -qE 'HTTP 500|does not match the expected' "$log_file" 2>/dev/null && ! $DRY_RUN; then
      # The retry hit the same format rejection -- don't go silent.
      # The operator needs to know this stage failed twice, not just
      # that a retry was attempted.
      echo "run_loop.sh: WARNING stage '$name' hit a format rejection again on retry in $log_file -- giving up on this stage, not a success" >&2
    fi
  elif [ "$goose_rc" -ne 0 ] && ! $DRY_RUN; then
    # Not a recognized retry/abort pattern, but goose (or `timeout`)
    # still exited nonzero -- surface it loudly instead of silently
    # treating a crashed/missing/timed-out stage as a success. The
    # stage's expected output file (PLAN.md, HANDOFF.md, ...) is most
    # likely missing now, which plan_has_unchecked() below treats as
    # "not done" -- but the operator needs to see why.
    echo "run_loop.sh: WARNING stage '$name' exited $goose_rc with no recognized retry/abort pattern in $log_file -- treating as a failed stage, not a success" >&2
  fi

  if ! commit_stage "$name" "$n" && ! $DRY_RUN; then
    echo "run_loop.sh: WARNING stage '$name' checkpoint commit failed -- the worktree's git history may be missing this stage's commit" >&2
  fi
  return 0
}

# Mechanical test stage: always runs for real (even under --dry-run).
run_test_stage() {
  local n
  n="$(next_step_n)"
  STAGES_RUN+=("test")
  {
    if [ -n "$TEST_CMD" ]; then
      (cd "$WORKTREE" && eval "$TEST_CMD")
    else
      echo "run_loop.sh: no test command available; test stage skipped"
      true
    fi
  } > "$WORKTREE/TEST_OUTPUT.txt" 2>&1
  local rc=$?
  if ! commit_stage "test" "$n" && ! $DRY_RUN; then
    echo "run_loop.sh: WARNING test-stage checkpoint commit failed -- the worktree's git history may be missing this stage's commit" >&2
  fi
  return "$rc"
}

abort_misconfigured() {
  echo "run_loop.sh: endpoint misconfigured (Resource not found in a goose log under $LOG_DIR)" >&2
  {
    echo "# LOOP_SUMMARY (aborted)"
    echo
    echo "Repo: $REPO_PATH"
    echo "Worktree: $WORKTREE"
    echo "Branch: $BRANCH"
    echo "Aborted: endpoint misconfigured"
    echo "Stages run: $STEP_N"
    echo "Stages: ${STAGES_RUN[*]}"
  } > "$WORKTREE/LOOP_SUMMARY.md"
  exit 2
}

finalize() {
  local final_test_rc="${1:-1}"
  local end_ts wall done_flag
  end_ts=$(date +%s)
  wall=$((end_ts - START_TS))
  if ! plan_has_unchecked && [ "$final_test_rc" -eq 0 ]; then
    done_flag=pass
  else
    done_flag=fail
  fi
  {
    echo "# LOOP_SUMMARY"
    echo
    echo "Repo: $REPO_PATH"
    echo "Worktree: $WORKTREE"
    echo "Branch: $BRANCH"
    echo "Dry run: $DRY_RUN"
    echo "Stages run: $STEP_N"
    echo "Stages: ${STAGES_RUN[*]}"
    echo "Iterations run: $ITER (max $MAX_ITERATIONS)"
    echo "Final test result: $([ "$final_test_rc" -eq 0 ] && echo PASS || echo FAIL)"
    echo "PLAN.md unchecked steps remaining: $(plan_has_unchecked && echo yes || echo no)"
    echo "Wall time: ${wall}s"
    echo
    echo "## Commits"
    git -C "$WORKTREE" log --oneline "$BASE_COMMIT"..HEAD 2>/dev/null
  } > "$WORKTREE/LOOP_SUMMARY.md"
  echo LOOP_DONE > "$WORKTREE/LOOP_DONE"
  if [ "$done_flag" = pass ]; then
    exit 0
  else
    exit 1
  fi
}

# --------------------------------------------------------------------
# Stage 1: plan (once)
# --------------------------------------------------------------------
START_TS=$(date +%s)
ITER=0
LAST_TEST_RC=1

run_model_stage plan "$PROMPTS_DIR/plan.md"
rc=$?
[ "$rc" -eq 3 ] && abort_misconfigured

# --------------------------------------------------------------------
# Loop: execute -> test -> review -> fix -> test, until PLAN.md has no
# unchecked steps and tests pass, or max-iterations is reached.
# --------------------------------------------------------------------
while [ "$ITER" -lt "$MAX_ITERATIONS" ]; do
  ITER=$((ITER + 1))

  run_model_stage execute "$PROMPTS_DIR/execute.md"
  rc=$?
  [ "$rc" -eq 3 ] && abort_misconfigured

  run_test_stage
  LAST_TEST_RC=$?

  git -C "$WORKTREE" diff "$BASE_COMMIT" HEAD > "$WORKTREE/DIFF.txt" 2>&1 || true

  run_model_stage review "$PROMPTS_DIR/review.md"
  rc=$?
  [ "$rc" -eq 3 ] && abort_misconfigured

  run_model_stage fix "$PROMPTS_DIR/fix.md"
  rc=$?
  [ "$rc" -eq 3 ] && abort_misconfigured

  run_test_stage
  LAST_TEST_RC=$?

  if ! plan_has_unchecked && [ "$LAST_TEST_RC" -eq 0 ]; then
    break
  fi
done

finalize "$LAST_TEST_RC"
