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
  LOOP_HARNESS_CMD     Optional. The CLI harness command to run each stage
                        through, with `{prompt}` substituted for the stage's
                        prompt file. Default: `goose run --no-session -i
                        {prompt}`. Set this to point the loop at a different
                        CLI harness that accepts a prompt file the same way;
                        Goose stays the default and its env vars (GOOSE_*)
                        are still exported to the command regardless of
                        which harness is configured.
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
COMMON_RULES_FILE="$PROMPTS_DIR/common-rules.md"

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
# Portable timeout: stock macOS ships no `timeout`. Use it if present,
# else `gtimeout` (Homebrew coreutils: `brew install coreutils`, only
# needed if you want the GNU tool specifically), else fall back to
# perl's alarm(), which ships with every macOS install and needs no
# extra package. All three paths are normalized to exit 124 on a
# timeout, the same code GNU `timeout` returns, so callers (the retry/
# abort logic below) see one contract regardless of which path ran.
# --------------------------------------------------------------------
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
elif command -v perl >/dev/null 2>&1; then
  TIMEOUT_BIN="perl"
else
  echo "run_loop.sh: no 'timeout', 'gtimeout', or 'perl' found on PATH -- cannot enforce per-stage timeouts. Install coreutils (brew install coreutils) or perl." >&2
  exit 1
fi

# run_with_timeout <seconds> <cmd...> -- runs <cmd...> under whichever
# timeout mechanism is available, mapping perl's alarm-kill exit (142)
# to 124 so every caller sees the same "timed out" contract as GNU
# `timeout`.
run_with_timeout() {
  local secs="$1"
  shift
  case "$TIMEOUT_BIN" in
    timeout|gtimeout)
      "$TIMEOUT_BIN" "$secs" "$@"
      ;;
    perl)
      perl -e 'alarm shift; exec @ARGV' -- "$secs" "$@"
      local rc=$?
      [ "$rc" -eq 142 ] && rc=124
      return "$rc"
      ;;
  esac
}

# Harness seam: the CLI command each stage is run through. `{prompt}` is
# substituted for the stage's prompt file. Goose is the shipped default;
# setting LOOP_HARNESS_CMD points the loop at any other CLI harness that
# accepts a prompt file the same way. See references/setup.md.
# (Two-step default, not `${LOOP_HARNESS_CMD:-...}`: bash's parameter-
# expansion brace matching ends at the first literal `}` in the default
# word, so a `{prompt}` inside it would truncate the expansion.)
if [ -z "${LOOP_HARNESS_CMD:-}" ]; then
  LOOP_HARNESS_CMD='goose run --no-session -i {prompt}'
fi

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

# Tracks the commit the review stage last saw, so each review's DIFF.txt
# covers only the delta since then, not the whole run. Starts at
# BASE_COMMIT (nothing reviewed yet).
LAST_REVIEWED_FILE="$WORKTREE/.loop-run/LAST_REVIEWED"
echo "$BASE_COMMIT" > "$LAST_REVIEWED_FILE"

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

# Extracts the first unchecked PLAN.md step into NEXT_STEP.md, so
# execute.md reads one step's text directly instead of scanning the
# whole checklist. PLAN.md stays authoritative and is only read back to
# tick the box once the step is done.
write_next_step() {
  if [ -f "$WORKTREE/PLAN.md" ]; then
    grep -m1 '\[ \]' "$WORKTREE/PLAN.md" > "$WORKTREE/NEXT_STEP.md" || true
  fi
  if [ ! -s "$WORKTREE/NEXT_STEP.md" ]; then
    echo "(no unchecked step found in PLAN.md)" > "$WORKTREE/NEXT_STEP.md"
  fi
}

commit_stage() {
  local name="$1" n="$2"
  if $DRY_RUN; then
    echo "[dry-run] would run: (cd $WORKTREE && git add -A && git commit --allow-empty -m \"loop: $name $n\")"
    return 0
  fi
  (cd "$WORKTREE" && git add -A && git commit --allow-empty -q -m "loop: $name $n")
}

# Single checkpoint-commit-or-warn path shared by run_model_stage and
# run_test_stage, so both report a failed commit the same way.
commit_or_warn() {
  local name="$1" n="$2"
  if ! commit_stage "$name" "$n" && ! $DRY_RUN; then
    echo "run_loop.sh: WARNING stage '$name' checkpoint commit failed -- the worktree's git history may be missing this stage's commit" >&2
  fi
}

# Builds the effective prompt goose actually reads: the stage prompt
# followed by the shared rules in common-rules.md, so the four rules
# (small steps, one file per write, test after each write, no delete/git
# beyond status+diff) live in exactly one file instead of being retyped
# in every stage prompt.
build_stage_prompt() {
  local base_prompt="$1" out="$2"
  cat "$base_prompt" "$COMMON_RULES_FILE" > "$out"
}

invoke_goose() {
  local prompt_file="$1" log_file="$2"
  local cmd=() quoted_prompt template
  # LOOP_HARNESS_CMD is parsed with normal shell word/quoting rules, not
  # naive whitespace splitting, so a quoted multi-word argument in the
  # template (e.g. --flag "quoted value") survives intact. `{prompt}` is
  # replaced first by a %q-quoted token (the prompt path is
  # driver-controlled, built under $LOG_DIR, so quoting it before eval
  # is just correctness, not a trust boundary), then the whole template
  # is eval'd into an array -- built once so the dry-run print and the
  # real call can never drift from each other.
  printf -v quoted_prompt '%q' "$prompt_file"
  template="${LOOP_HARNESS_CMD//\{prompt\}/$quoted_prompt}"
  eval "cmd=( $template )"

  if $DRY_RUN; then
    echo "[dry-run] would run: (cd $WORKTREE && env XDG_CONFIG_HOME=$GOOSE_CONFIG_DIR OPENAI_HOST=$OPENAI_HOST OPENAI_API_KEY=*** GOOSE_PROVIDER=openai GOOSE_MODEL=$GOOSE_MODEL GOOSE_DISABLE_KEYRING=1 GOOSE_TELEMETRY_ENABLED=false $TIMEOUT_BIN $STAGE_TIMEOUT $(printf '%q ' "${cmd[@]}")) > $log_file 2>&1"
    : > "$log_file"
    return 0
  fi
  (
    cd "$WORKTREE" || exit 99
    export XDG_CONFIG_HOME="$GOOSE_CONFIG_DIR"
    export OPENAI_HOST="$OPENAI_HOST" OPENAI_API_KEY="$OPENAI_API_KEY"
    export GOOSE_PROVIDER=openai GOOSE_MODEL="$GOOSE_MODEL" GOOSE_DISABLE_KEYRING=1
    export GOOSE_TELEMETRY_ENABLED=false
    run_with_timeout "$STAGE_TIMEOUT" "${cmd[@]}"
  ) > "$log_file" 2>&1
  return $?
}

# Retry trigger, general rule: any HTTP 500 means the tool-call grammar
# rejected a malformed call, on any OpenAI-compatible server.
RETRY_TRIGGER_HTTP_500='HTTP 500'
# Retry trigger, documented fallback: llama.cpp's own rejection message,
# kept in case a proxy or client strips the "HTTP 500" text but passes
# this fragment through. Comes from llama.cpp's grammar-constrained
# decoding path specifically -- not a general server behavior, so it is
# checked separately rather than folded into the regex above as if the
# two were equivalent.
RETRY_TRIGGER_LLAMACPP_FALLBACK='does not match the expected'

log_has_retry_trigger() {
  grep -qE "$RETRY_TRIGGER_HTTP_500" "$1" 2>/dev/null \
    || grep -qF "$RETRY_TRIGGER_LLAMACPP_FALLBACK" "$1" 2>/dev/null
}

# Runs one fresh-context goose stage, retrying once on a format
# rejection (HTTP 500, or llama.cpp's fallback message) and aborting the
# whole loop on a 404 ("Resource not found"). Returns 0 on success, 3
# to signal "abort: endpoint misconfigured".
run_model_stage() {
  local name="$1" prompt_file="$2"
  local n log_file goose_rc attempt built_prompt
  STAGES_RUN+=("$name")

  built_prompt="$LOG_DIR/${name}_prompt.md"
  build_stage_prompt "$prompt_file" "$built_prompt"

  for attempt in 1 2; do
    n="$(next_step_n)"
    if [ "$attempt" -eq 1 ]; then
      log_file="$LOG_DIR/${name}_${n}.log"
    else
      log_file="$LOG_DIR/${name}_${n}_retry.log"
    fi

    invoke_goose "$built_prompt" "$log_file"
    goose_rc=$?

    if grep -q 'Resource not found' "$log_file" 2>/dev/null; then
      return 3
    fi

    if log_has_retry_trigger "$log_file"; then
      if [ "$attempt" -lt 2 ]; then
        echo "run_loop.sh: stage '$name' hit a format rejection; retrying once" >&2
        continue
      elif ! $DRY_RUN; then
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
    break
  done

  commit_or_warn "$name" "$n"
  return 0
}

# Runs a model stage and aborts the whole loop immediately if it signals
# "endpoint misconfigured" (exit code 3), instead of repeating the
# rc-check at every call site.
stage_or_abort() {
  run_model_stage "$@"
  local rc=$?
  [ "$rc" -eq 3 ] && abort_misconfigured
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
  commit_or_warn "test" "$n"
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

stage_or_abort plan "$PROMPTS_DIR/plan.md"

# --------------------------------------------------------------------
# Loop: execute -> test -> review -> fix -> test, until PLAN.md has no
# unchecked steps and tests pass, or max-iterations is reached.
# --------------------------------------------------------------------
while [ "$ITER" -lt "$MAX_ITERATIONS" ]; do
  ITER=$((ITER + 1))

  write_next_step

  stage_or_abort execute "$PROMPTS_DIR/execute.md"

  run_test_stage
  LAST_TEST_RC=$?

  # DIFF.txt (read by review.md) covers only the delta since the last
  # review, so each pass prefills just the new work. FULL_DIFF.txt keeps
  # the whole run's diff available under a different name for the
  # summary. Both live under .loop-run/ (gitignored), not the worktree
  # root -- committing DIFF.txt itself into the worktree would make its
  # own past content part of the next iteration's diff.
  LAST_REVIEWED="$(cat "$LAST_REVIEWED_FILE" 2>/dev/null || echo "$BASE_COMMIT")"
  git -C "$WORKTREE" diff "$BASE_COMMIT" HEAD > "$WORKTREE/.loop-run/FULL_DIFF.txt" 2>&1 || true
  git -C "$WORKTREE" diff "$LAST_REVIEWED" HEAD > "$WORKTREE/.loop-run/DIFF.txt" 2>&1 || true
  git -C "$WORKTREE" rev-parse HEAD > "$LAST_REVIEWED_FILE"

  stage_or_abort review "$PROMPTS_DIR/review.md"

  stage_or_abort fix "$PROMPTS_DIR/fix.md"

  run_test_stage
  LAST_TEST_RC=$?

  if ! plan_has_unchecked && [ "$LAST_TEST_RC" -eq 0 ]; then
    break
  fi
done

finalize "$LAST_TEST_RC"
