#!/usr/bin/env bash
# Unattended agent loop driver for a local-LLM-backed Goose agent.
#
# Usage:
#   run_loop.sh <repo_path> <plan_file> [--max-iterations N] [--test-cmd "..."] [--dry-run]
#
# Runs a plan through a fresh-context Goose stage sequence
# (plan -> execute -> test -> gates, looping until the plan has no
# unchecked steps and tests pass, or --max-iterations is reached) in a
# disposable git worktree, committing after every stage. The gates are
# three fresh-context review passes in a fixed order -- simplify,
# security, review -- each followed by a fix stage and a test stage
# when it reports findings, capped at two fix rounds per gate per
# iteration (a third round means the approach is wrong, not that the
# fixes are nearly done; the loop stops and reports "not converged"). The endpoint is passed as explicit environment
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
Usage: run_loop.sh <repo_path> <plan_file> [--max-iterations N] [--test-cmd "..."] [--gates LIST] [--dry-run]

  <repo_path>          Path to an existing git repo to run the loop against.
  <plan_file>          Path to a file describing the task to plan and execute.
  --max-iterations N   Cap on execute/test/gates cycles (default 3).
  --gates LIST         Comma-separated gates to run after each execute, in
                        this fixed order: simplify,security,review (the
                        default). "none" skips every gate. Each gate that
                        reports findings is followed by a fix stage and a
                        test stage, at most twice per gate per iteration.
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
  LOOP_DIFF_SPLIT_BYTES
                       Optional. When an iteration's diff is larger than
                        this many bytes and touches more than one file, each
                        gate runs once per changed file on that file's diff
                        alone, so no single prompt carries the whole diff
                        (default 32768, about 8K tokens).
  LOOP_GATE_ROUNDS     Optional. Fix rounds allowed per gate per iteration
                        before the loop stops as "not converged" (default 2).
  LOOP_GATE_TIMEOUT    Optional. Per-stage timeout for the gate stages in
                        seconds (default 300). A gate writes at most ten
                        lines, so a gate still running at this limit is a
                        runaway generation, not slow work.
  LOOP_MAX_TOKENS      Optional. Output-token cap for the gate stages, sent
                        to the harness as GOOSE_MAX_TOKENS (default 8192).
                        A gate holds only the write tool, so the tool set
                        bounds a runaway and this only has to fit one
                        findings file.
  LOOP_GATE_DIFF_BYTES Optional. Bytes of diff a gate prompt may carry
                        (default 32768). Separate from the split
                        threshold: one oversized file is capped even when
                        no split happened.
  LOOP_STAGE_MAX_TOKENS
                       Optional. The same cap for plan, execute and fix
                        stages, which write files (default 8192). A write
                        cut at the cap is retried once with a reminder to
                        split it.
                       All timeouts and caps must be integers of at least 1.
  LOOP_HARNESS_CMD     Optional. The CLI harness command to run each stage
                        through, with `{prompt}` substituted for the stage's
                        prompt file. Default: `goose run --no-session -i
                        {prompt}`. Set this to point the loop at a different
                        CLI harness that accepts a prompt file the same way;
                        Goose stays the default and its env vars (GOOSE_*)
                        are still exported to the command regardless of
                        which harness is configured. The token caps
                        below are delivered through GOOSE_MAX_TOKENS, so
                        another harness ignores them and only the stage
                        timeouts bound it.
EOF
}

# --------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------
DRY_RUN=false
MAX_ITERATIONS=3
TEST_CMD_OVERRIDE=""
GATES_SPEC="simplify,security,review"
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
    --gates)
      if [ $# -lt 2 ]; then
        echo "run_loop.sh: --gates requires a value" >&2
        exit 1
      fi
      GATES_SPEC="$2"
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
GATE_RULES_FILE="$PROMPTS_DIR/gate-rules.md"

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
DIFF_SPLIT_BYTES="${LOOP_DIFF_SPLIT_BYTES:-32768}"
GATE_ROUNDS="${LOOP_GATE_ROUNDS:-2}"
GATE_TIMEOUT="${LOOP_GATE_TIMEOUT:-300}"
# 8192, not the 3072 tool-calling figure: a gate holds only `write`, so
# the tool set stops a runaway at the source and the cap only has to be
# large enough for one findings file. Measured at 3072 the same gate
# prompt was cut mid tool call in 1 of 2 live attempts.
MAX_TOKENS="${LOOP_MAX_TOKENS:-8192}"
STAGE_MAX_TOKENS="${LOOP_STAGE_MAX_TOKENS:-8192}"
# How much diff text a gate prompt may carry. Separate from the split
# threshold on purpose: the threshold decides when to review file by
# file, this decides how much of whatever is left gets pasted, and one
# oversized single file must be capped even when no split happened.
GATE_DIFF_BYTES="${LOOP_GATE_DIFF_BYTES:-32768}"
# require_int <name> <value> <min>: the one numeric check for every knob.
# Timeouts and token caps take min 1: 0 means "no limit" to GNU timeout
# and to perl's alarm, and goose rejects a 0 cap, so 0 is refused here
# rather than silently disabling the bound.
require_int() {
  case "$2" in
    ''|*[!0-9]*) ;;
    *) [ "$2" -ge "$3" ] && return 0 ;;
  esac
  if [ "$3" -eq 0 ]; then
    echo "run_loop.sh: $1 must be a non-negative integer, got '$2'" >&2
  else
    echo "run_loop.sh: $1 must be an integer of at least $3, got '$2'" >&2
  fi
  exit 1
}
require_int LOOP_DIFF_SPLIT_BYTES "$DIFF_SPLIT_BYTES" 0
require_int LOOP_GATE_ROUNDS "$GATE_ROUNDS" 0
require_int LOOP_STAGE_TIMEOUT "$STAGE_TIMEOUT" 1
require_int LOOP_GATE_TIMEOUT "$GATE_TIMEOUT" 1
require_int LOOP_MAX_TOKENS "$MAX_TOKENS" 1
require_int LOOP_STAGE_MAX_TOKENS "$STAGE_MAX_TOKENS" 1
require_int LOOP_GATE_DIFF_BYTES "$GATE_DIFF_BYTES" 1
# A gate never gets a longer timeout than an ordinary stage.
if [ "$GATE_TIMEOUT" -gt "$STAGE_TIMEOUT" ]; then
  echo "run_loop.sh: LOOP_GATE_TIMEOUT=$GATE_TIMEOUT is above LOOP_STAGE_TIMEOUT=$STAGE_TIMEOUT; using $STAGE_TIMEOUT for the gates" >&2
  GATE_TIMEOUT="$STAGE_TIMEOUT"
fi

# --------------------------------------------------------------------
# Gates: which fresh-context review passes run after each execute, and
# which file each one writes. Order is fixed (simplify, then security,
# then review) regardless of the order given on the command line.
# --------------------------------------------------------------------
GATES=()
if [ "$GATES_SPEC" != "none" ]; then
  _spec_items=()
  IFS=',' read -r -a _spec_items <<< "$GATES_SPEC"
  if [ "${#_spec_items[@]}" -eq 0 ]; then
    echo "run_loop.sh: --gates: empty list; name gates, or pass 'none' to skip them on purpose" >&2
    exit 1
  fi
  for g in "${_spec_items[@]}"; do
    case "$g" in
      simplify|security|review|"") ;;
      *)
        echo "run_loop.sh: --gates: unknown gate '$g' (known: simplify, security, review, none)" >&2
        exit 1
        ;;
    esac
  done
  # Fixed order regardless of how the list was written.
  for g in simplify security review; do
    for item in "${_spec_items[@]}"; do
      [ "$item" = "$g" ] && GATES+=("$g") && break
    done
  done
  if [ "${#GATES[@]}" -eq 0 ]; then
    echo "run_loop.sh: --gates '$GATES_SPEC' names no gate; pass 'none' to skip them on purpose" >&2
    exit 1
  fi
fi

gate_output_file() {
  case "$1" in
    simplify) echo SIMPLIFY.md ;;
    security) echo SECURITY.md ;;
    review)   echo REVIEW.md ;;
  esac
}

# The one place that decides whether a stage name is a gate. Every
# gate-specific behaviour (extra prompt rules, shorter timeout, smaller
# output cap) asks here, and run_model_stage asks once per stage.
is_gate() {
  [ -n "$(gate_output_file "$1")" ]
}

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
# timeout mechanism is available, exiting 124 on a timeout so every
# caller sees the same contract as GNU `timeout`.
#
# The perl fallback runs the command in its own process group and
# signals the group, not just the command: a harness that spawns a shell
# tool would otherwise leave those children running after the timeout,
# reparented to init (observed on macOS, where no GNU timeout exists).
run_with_timeout() {
  local secs="$1"
  shift
  case "$TIMEOUT_BIN" in
    timeout|gtimeout)
      "$TIMEOUT_BIN" "$secs" "$@"
      ;;
    perl)
      perl -e '
        my $secs = shift;
        my $pid = fork();
        die "run_with_timeout: fork failed: $!\n" unless defined $pid;
        if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127; }
        $SIG{ALRM} = sub {
          kill("TERM", -$pid);
          select(undef, undef, undef, 0.5);
          kill("KILL", -$pid);
          exit 124;
        };
        alarm $secs;
        waitpid($pid, 0);
        alarm 0;
        my $st = $?;
        exit($st & 127 ? 128 + ($st & 127) : $st >> 8);
      ' -- "$secs" "$@"
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
# The driver removes and rewrites its bookkeeping files at the worktree
# root. A target repo that tracks one of those names (a GitHub-style
# SECURITY.md, say) would lose it, so refuse up front.
for f in PLAN.md PLAN_INPUT.md HANDOFF.md NEXT_STEP.md TEST_OUTPUT.txt \
         FINDINGS.md NEEDS_HUMAN.md SIMPLIFY.md SECURITY.md REVIEW.md; do
  if git -C "$REPO_PATH" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    echo "run_loop.sh: $REPO_PATH tracks $f at its root, a name the loop driver overwrites; rename it or run the loop on a copy" >&2
    exit 1
  fi
done

# Nothing under .loop-run/ may be tracked. git checks those files out
# into every new worktree, so a tracked symlink there would be waiting
# at a path the driver writes, and would redirect that write out of the
# worktree. The driver owns that directory; the repo must not.
if [ -n "$(git -C "$REPO_PATH" ls-files -- '.loop-run' 2>/dev/null)" ]; then
  echo "run_loop.sh: $REPO_PATH tracks files under .loop-run/, a directory the loop driver owns and writes; remove them from the index or run the loop on a copy" >&2
  exit 1
fi

TS0="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$REPO_PATH/.loop"
# Two runs in the same second (a dry run right after a real one, or two
# concurrent starts) must not collide on the worktree name or the
# branch. git's own add is the check: on failure, try the next suffix.
_k=1
TS="$TS0"
while :; do
  BRANCH="loop/$TS"
  WORKTREE="$REPO_PATH/.loop/$TS"
  # stderr into this process's own variable: a file under .loop/ would
  # be truncated by a concurrent run and report the wrong cause, or none.
  if _add_err="$(git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE" 2>&1 >/dev/null)"; then
    break
  fi
  _k=$((_k + 1))
  if [ "$_k" -gt 20 ]; then
    echo "run_loop.sh: git worktree add failed: $_add_err" >&2
    exit 1
  fi
  TS="$TS0-$_k"
done
echo "run_loop.sh: created worktree $WORKTREE on branch $BRANCH"

BASE_COMMIT="$(git -C "$WORKTREE" rev-parse HEAD)"
LOG_DIR="$WORKTREE/.loop-run/logs"
GOOSE_CONFIG_DIR="$WORKTREE/.loop-run/goose-config"
# Gates run under their own config, exposing `write` and nothing else.
# A gate is handed the diff in its prompt, so it needs no tool that can
# read: removing them is what stops a gate listing source into its reply
# until the output cap or the gate timeout stops it (issues #40, #42).
GATE_CONFIG_DIR="$WORKTREE/.loop-run/goose-config-gate"
mkdir -p "$LOG_DIR" "$GOOSE_CONFIG_DIR/goose" "$GATE_CONFIG_DIR/goose"

# Tracks the commit the review stage last saw, so each review's DIFF.txt
# covers only the delta since then, not the whole run. Starts at
# BASE_COMMIT (nothing reviewed yet).
LAST_REVIEWED_FILE="$WORKTREE/.loop-run/LAST_REVIEWED"
echo "$BASE_COMMIT" > "$LAST_REVIEWED_FILE"
rm -f "$WORKTREE/.loop-run/REJECTED_FINDINGS.md"

# Seed this run's isolated Goose config: from $XDG_CONFIG_HOME/goose/config.yaml
# if the caller pointed one at us, else from the bundled hardened example.
if [ -n "${XDG_CONFIG_HOME:-}" ] && [ -f "$XDG_CONFIG_HOME/goose/config.yaml" ]; then
  cp "$XDG_CONFIG_HOME/goose/config.yaml" "$GOOSE_CONFIG_DIR/goose/config.yaml"
else
  cp "$BUNDLED_GOOSE_CONFIG" "$GOOSE_CONFIG_DIR/goose/config.yaml"
fi

# The gate config is the stage config with the developer extension's
# available_tools cut to `write`. Derived rather than tracked separately,
# so a provider or telemetry change in the operator's config reaches the
# gates too.
#
# The edit is scoped to the developer block's available_tools list, and
# the result is then verified to expose exactly `write`. A config whose
# list is written in another shape (flow style, a different indent) is
# refused rather than passed through: silently leaving `shell` in a gate
# would defeat the whole point of the gate config.
# Removes a symlink at a path the driver is about to write, so a
# planted link can never redirect a driver write.
unlink_if_symlink() {
  [ -L "$1" ] && rm -f "$1"
  return 0
}

# derive_gate_tools <config>: the stage config with the developer
# extension's available_tools cut to `write`, and every other extension
# forced off. Disabling them here, rather than refusing a config that
# enables one, keeps a legitimate operator setup working: the extension
# stays on for plan, execute and fix, and only the gates lose it.
derive_gate_tools() {
  awk '
    # Track the current extension block and its available_tools list.
    /^  [a-zA-Z0-9_-]+:/ {
      name = $0; sub(/^  /, "", name); sub(/:.*$/, "", name)
      in_dev = (name == "developer"); in_list = 0
    }
    in_dev && /^    [a-zA-Z_]+:/ { in_list = ($0 ~ /^    available_tools:/) }
    in_list && /^      - /    { if ($0 != "      - write") next }
    in_list && !/^      - / && !/^    available_tools:/ { in_list = 0 }
    # Any other extension brings its own tools; a gate gets none of them.
    # The value is parsed rather than matched literally, so a trailing
    # comment cannot leave an extension enabled.
    !in_dev && /^    enabled:[[:space:]]*/ {
      v = $0
      sub(/^    enabled:[[:space:]]*/, "", v)
      sub(/[[:space:]]*(#.*)?$/, "", v)
      if (v == "true") sub(/true/, "false")
    }
    { print }
  ' "$1"
}

# gate_tools <config>: the developer extension's available_tools, one per
# line, or nothing when the list is not in the expected block shape.
gate_tools() {
  awk '
    # Same block regex as derive_gate_tools: a narrower one here would
    # attribute the tools of a later extension to developer and refuse a
    # valid config.
    /^  [a-zA-Z0-9_-]+:/      { in_dev = ($0 ~ /^  developer:/); in_list = 0 }
    in_dev && /^    [a-zA-Z_]+:/ { in_list = ($0 ~ /^    available_tools:/) }
    in_list && /^      - /    { print substr($0, 9) }
  ' "$1"
}

# ensure_gate_config: rebuild the gate config from the stage config and
# verify it exposes exactly `write`. Called at setup and again before
# every gate stage: the gate config lives inside the worktree, which a
# stage holding `shell` can write, so deriving it once would let an
# earlier stage put `shell` back for every later gate.
# enabled_extensions <config>: the name of every extension block whose
# body sets `enabled: true`.
# Parses the value independently of the pattern derive_gate_tools
# rewrites. If the two shared a regex, this could only confirm that the
# substitution ran, never catch what it failed to match.
enabled_extensions() {
  awk '
    /^  [a-zA-Z0-9_-]+:/ { name = $0; sub(/^  /, "", name); sub(/:.*$/, "", name) }
    /^    enabled:[[:space:]]*/ {
      v = $0
      sub(/^    enabled:[[:space:]]*/, "", v)
      sub(/[[:space:]]*(#.*)?$/, "", v)
      if (v == "true" && name != "") print name
    }
  ' "$1"
}

# ensure_gate_config: rebuild the gate config from the stage config and
# verify it leaves a gate with the write tool and nothing else. Returns
# 1 rather than exiting, so the caller decides how to fail.
#
# Called at setup and again before every gate stage: the gate config
# lives inside the worktree, which a stage holding `shell` can write, so
# deriving it once would let an earlier stage put the tools back for
# every later gate.
ensure_gate_config() {
  local tools extras
  # Outermost first: clearing the child through a symlinked parent
  # would delete at the link's target instead.
  unlink_if_symlink "$GATE_CONFIG_DIR"
  unlink_if_symlink "$GATE_CONFIG_DIR/goose"
  mkdir -p "$GATE_CONFIG_DIR/goose"
  unlink_if_symlink "$GATE_CONFIG_DIR/goose/config.yaml"
  derive_gate_tools "$GOOSE_CONFIG_DIR/goose/config.yaml" > "$GATE_CONFIG_DIR/goose/config.yaml"
  tools="$(gate_tools "$GATE_CONFIG_DIR/goose/config.yaml" | tr '\n' ',' | sed 's/,$//')"
  if [ "$tools" != "write" ]; then
    echo "run_loop.sh: could not cut the gate tool set down to 'write' alone (got '${tools:-nothing}')." >&2
    echo "run_loop.sh: the Goose config's developer extension must list available_tools as one '      - <tool>' line each, including write. See references/setup.md." >&2
    return 1
  fi
  # available_tools only covers the developer extension, so verify the
  # derivation actually turned every other extension off: several of
  # them read files, which is what a gate must not be able to do.
  extras="$(enabled_extensions "$GATE_CONFIG_DIR/goose/config.yaml" | grep -v '^developer$' | tr '\n' ',' | sed 's/,$//')"
  if [ -n "$extras" ]; then
    echo "run_loop.sh: could not disable extensions besides developer in the gate config ($extras); a gate would get their tools. See references/setup.md." >&2
    return 1
  fi
}

ensure_gate_config || exit 1

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
PROMPT_SEQ=0
STAGES_RUN=()

# Increments STEP_N in the calling shell; read $STEP_N afterwards.
# (A command substitution would run it in a subshell and lose the
# increment, so every stage would be "1".)
next_step_n() {
  STEP_N=$((STEP_N + 1))
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
  unlink_if_symlink "$WORKTREE/NEXT_STEP.md"
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
# longest_fence <file...>: a backtick fence at least three long and
# longer than any backtick run in the given files.
longest_fence() {
  local n
  n="$(cat "$@" 2>/dev/null | grep -o '`\{1,\}' | awk '
    { if (length($0) > m) m = length($0) }
    END { print (m < 3 ? 3 : m + 1) }
  ')"
  [ -n "$n" ] || n=3
  printf '%*s' "$n" '' | tr ' ' '`'
}

# Gate stages additionally get gate-rules.md (the one copy of the
# findings-file format that filter_findings' FINDING_RE parses) and the
# diff itself, pasted in. A gate has no tool that can read a file, so
# the prompt is the only way the diff can reach it.
build_stage_prompt() {
  local base_prompt="$1" out="$2" name="$3"
  if is_gate "$name"; then
    # Not common-rules.md: it tells the model to run the test command and
    # git, tools a gate does not have. gate-rules.md is the gate's own
    # shared text.
    cat "$base_prompt" "$GATE_RULES_FILE" > "$out"
    local diff_file="$WORKTREE/.loop-run/DIFF.txt" fence diff_bytes
    # A gate that saw only part of the change must not read as a clean
    # review, so the driver records the truncation too, not just the
    # note inside the prompt.
    DIFF_TRUNCATED_TO=0
    diff_bytes="$(wc -c < "$diff_file" 2>/dev/null || echo 0)"
    if [ "$diff_bytes" -gt "$GATE_DIFF_BYTES" ]; then
      DIFF_TRUNCATED_TO="$diff_bytes"
      echo "run_loop.sh: gate '$name' was shown $GATE_DIFF_BYTES of $diff_bytes diff bytes (LOOP_GATE_DIFF_BYTES)" >&2
    fi
    # A fence longer than the longest backtick run in the pasted text, so
    # a diff that touches a Markdown file cannot close the block early
    # and turn the rest of the diff into apparent instructions.
    fence="$(longest_fence "$diff_file" "$WORKTREE/TEST_OUTPUT.txt")"
    {
      printf '\n## The diff under review\n\n'
      if [ -s "$diff_file" ]; then
        printf '%s diff\n' "$fence"
        # Capped even when the per-file split did not trigger: one
        # oversized file would otherwise paste its whole diff here.
        head -c "$GATE_DIFF_BYTES" "$diff_file"
        if [ "$DIFF_TRUNCATED_TO" -gt 0 ]; then
          printf '\n[truncated at %s of %s bytes; review what is shown]\n' \
            "$GATE_DIFF_BYTES" "$DIFF_TRUNCATED_TO"
        fi
        printf '\n%s\n' "$fence"
      else
        printf '(empty: nothing changed since the last review)\n'
      fi
      if [ -s "$WORKTREE/TEST_OUTPUT.txt" ]; then
        printf '\n## Latest test run\n\n%s\n' "$fence"
        tail -n 40 "$WORKTREE/TEST_OUTPUT.txt"
        # Leading newline: test output whose last line has none would
        # otherwise leave the block unclosed, and a retry nudge appended
        # after it would read as more test output.
        printf '\n%s\n' "$fence"
      fi
    } >> "$out"
  else
    cat "$base_prompt" "$COMMON_RULES_FILE" > "$out"
  fi
}

# invoke_goose <prompt> <log> <timeout> <max_tokens>: the last two are
# required so a call site can never silently fall back to the long
# budget for a gate.
invoke_goose() {
  local prompt_file="$1" log_file="$2" stage_timeout="${3:?invoke_goose: timeout required}" max_tokens="${4:?invoke_goose: max_tokens required}" config_dir="${5:?invoke_goose: config dir required}"
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

  # One environment list, used by both the dry-run print and the real
  # call, so the two can never drift. GOOSE_MAX_TOKENS is the output cap
  # for this stage: a runaway generation stops at the server after it
  # instead of running to the stage timeout.
  local -a stage_env=(
    "XDG_CONFIG_HOME=$config_dir"
    "OPENAI_HOST=$OPENAI_HOST"
    "OPENAI_API_KEY=$OPENAI_API_KEY"
    "GOOSE_PROVIDER=openai"
    "GOOSE_MODEL=$GOOSE_MODEL"
    "GOOSE_MAX_TOKENS=$max_tokens"
    "GOOSE_DISABLE_KEYRING=1"
    "GOOSE_TELEMETRY_ENABLED=false"
  )

  if $DRY_RUN; then
    local -a shown=()
    local kv
    for kv in "${stage_env[@]}"; do
      case "$kv" in
        OPENAI_API_KEY=*) shown+=("OPENAI_API_KEY=***") ;;
        *) shown+=("$kv") ;;
      esac
    done
    echo "[dry-run] would run: (cd $WORKTREE && env $(printf '%s ' "${shown[@]}")$TIMEOUT_BIN $stage_timeout $(printf '%q ' "${cmd[@]}")) > $log_file 2>&1"
    : > "$log_file"
    return 0
  fi
  (
    cd "$WORKTREE" || exit 99
    local kv
    for kv in "${stage_env[@]}"; do export "$kv"; done
    run_with_timeout "$stage_timeout" "${cmd[@]}" < /dev/null
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
# Retry trigger, output cap: goose 1.50 ends a run with one of three
# notices when the response was cut at GOOSE_MAX_TOKENS. The retry nudge
# tells the model to split the write, or to stop printing file contents,
# instead of raising the cap.
# Anchored at line start: goose prints each notice as its own line,
# while a model quoting this file's source (a gate reviewing run_loop.sh
# does exactly that) emits the text indented or line-numbered inside its
# reply. Anchoring keeps the driver from reading a quotation of itself as
# its own truncation.
RETRY_TRIGGER_TRUNCATED='^Warning: Response reached the model.s output-token limit|^[a-z]*:? ?[Ii]t hit the output token limit while generating|^.*[Ww]ere truncated because the model reached its output token limit'
# Matched in the last few lines only: the notice is the last thing goose
# prints, so a mid-run mention is not this run being truncated.
RETRY_LOG_TAIL=5

# retry_trigger_kind <log>: "truncated", "format", or empty. The one
# place that decides, so no caller re-derives which pattern matched.
retry_trigger_kind() {
  if tail -n "$RETRY_LOG_TAIL" "$1" 2>/dev/null | grep -qE "$RETRY_TRIGGER_TRUNCATED"; then
    echo truncated
  elif grep -qE "$RETRY_TRIGGER_HTTP_500" "$1" 2>/dev/null \
    || grep -qF "$RETRY_TRIGGER_LLAMACPP_FALLBACK" "$1" 2>/dev/null; then
    echo format
  fi
}

# Retry prompts differ from the first attempt on purpose: at temperature
# 0 the model is deterministic, so re-sending the identical prompt after
# a malformed call or a missing output file would replay the same path.
# One appended line changes the prefix and gives the model the reason.
RETRY_NUDGE_FORMAT='Note: the previous attempt produced a malformed tool call. Keep every tool call small, under 300 tokens, one file per call.'
RETRY_NUDGE_TRUNCATED='Note: the previous attempt was cut off at the output limit. Split the work: write one file per call and keep each write under 500 lines.'
RETRY_NUDGE_TRUNCATED_GATE='Note: the previous attempt was cut off at the output limit because it printed file contents. Do not print file contents in your reply. Write %s at the root of the current directory first, in one call, then stop.'
RETRY_NUDGE_MISSING='Note: the previous attempt ended without writing %s. Write %s at the root of the current directory now, in one call, then stop.'

# Runs one fresh-context goose stage, retrying once on a format
# rejection (HTTP 500, or llama.cpp's fallback message) or on a missing
# expected output file, and aborting the whole loop on a 404 ("Resource
# not found"). Returns 0 on success, 3 to signal "abort: endpoint
# misconfigured".
#   $3 (optional): a file, relative to the worktree, the stage must have
#   written; when absent after the first attempt the stage is retried
#   once with a reminder appended to the prompt. Missing after the
#   retry is the caller's problem (gates fail closed on it).
run_model_stage() {
  local name="$1" prompt_file="$2" expected="${3:-}"
  local n log_file goose_rc attempt built_prompt retry_prompt nudge stage_timeout max_tokens trigger config_dir
  STAGES_RUN+=("$name")
  if is_gate "$name"; then
    stage_timeout="$GATE_TIMEOUT"
    max_tokens="$MAX_TOKENS"
    config_dir="$GATE_CONFIG_DIR"
    ensure_gate_config || abort_run "gate config no longer safe"
  else
    stage_timeout="$STAGE_TIMEOUT"
    max_tokens="$STAGE_MAX_TOKENS"
    config_dir="$GOOSE_CONFIG_DIR"
  fi

  PROMPT_SEQ=$((PROMPT_SEQ + 1))
  built_prompt="$LOG_DIR/${name}_prompt_${PROMPT_SEQ}.md"
  retry_prompt="$LOG_DIR/${name}_prompt_${PROMPT_SEQ}_retry.md"
  unlink_if_symlink "$built_prompt"
  unlink_if_symlink "$retry_prompt"
  build_stage_prompt "$prompt_file" "$built_prompt" "$name"

  for attempt in 1 2; do
    next_step_n; n="$STEP_N"
    # Each attempt starts with the stage's output file gone, so a file
    # left by attempt 1 can never be mistaken for attempt 2's work.
    [ -n "$expected" ] && rm -f "$WORKTREE/$expected"
    if [ "$attempt" -eq 1 ]; then
      log_file="$LOG_DIR/${name}_${n}.log"
      LAST_STAGE_LOG="$log_file"
      invoke_goose "$built_prompt" "$log_file" "$stage_timeout" "$max_tokens" "$config_dir"
    else
      log_file="$LOG_DIR/${name}_${n}_retry.log"
      LAST_STAGE_LOG="$log_file"
      { cat "$built_prompt"; printf '\n%s\n' "$nudge"; } > "$retry_prompt"
      invoke_goose "$retry_prompt" "$log_file" "$stage_timeout" "$max_tokens" "$config_dir"
    fi
    goose_rc=$?

    if grep -q 'Resource not found' "$log_file" 2>/dev/null; then
      return 3
    fi

    trigger="$(retry_trigger_kind "$log_file")"
    if [ -n "$trigger" ]; then
      if [ "$attempt" -lt 2 ]; then
        if [ "$trigger" = truncated ]; then
          echo "run_loop.sh: stage '$name' was cut at the output cap; retrying once with a split reminder" >&2
          if is_gate "$name"; then
            printf -v nudge "$RETRY_NUDGE_TRUNCATED_GATE" "$(gate_output_file "$name")"
          else
            nudge="$RETRY_NUDGE_TRUNCATED"
          fi
        else
          echo "run_loop.sh: stage '$name' hit a format rejection; retrying once" >&2
          nudge="$RETRY_NUDGE_FORMAT"
        fi
        continue
      elif ! $DRY_RUN; then
        # The retry hit the same format rejection -- don't go silent.
        # The operator needs to know this stage failed twice, not just
        # that a retry was attempted.
        echo "run_loop.sh: WARNING stage '$name' hit a format rejection again on retry in $log_file -- giving up on this stage, not a success" >&2
      fi
    else
      if [ "$goose_rc" -ne 0 ] && ! $DRY_RUN; then
        # Not a recognized retry/abort pattern, but goose (or `timeout`)
        # still exited nonzero -- surface it loudly instead of silently
        # treating a crashed/missing/timed-out stage as a success.
        echo "run_loop.sh: WARNING stage '$name' exited $goose_rc with no recognized retry/abort pattern in $log_file" >&2
      fi
      if [ -n "$expected" ] && [ ! -f "$WORKTREE/$expected" ] && ! $DRY_RUN; then
        # The model answered in prose, stopped, crashed, or timed out
        # without writing the file this stage exists to produce. One
        # nudged retry whatever the cause; the retry is the only one.
        if [ "$attempt" -lt 2 ]; then
          echo "run_loop.sh: stage '$name' did not write $expected; retrying with a write reminder" >&2
          printf -v nudge "$RETRY_NUDGE_MISSING" "$expected" "$expected"
          continue
        fi
        echo "run_loop.sh: WARNING stage '$name' did not write $expected on the retry either -- treating as a failed stage, not a success" >&2
      fi
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
  next_step_n; n="$STEP_N"
  STAGES_RUN+=("test")
  unlink_if_symlink "$WORKTREE/TEST_OUTPUT.txt"
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

# --------------------------------------------------------------------
# Gate machinery
# --------------------------------------------------------------------
GATE_LOG=()          # one line per gate run, for LOOP_SUMMARY.md
GATES_FAILED=()      # gates that wrote no output even after the retry
NOT_CONVERGED=""     # the gate that still had findings after GATE_ROUNDS fixes
DELETES_REVERTED=0   # fix stages whose deleted files the driver restored
LAST_STAGE_LOG=""    # the log of the most recent model attempt
GATE_RECOVERED=""    # set when a gate verdict was read from the reply
DIFF_TRUNCATED_TO=0  # bytes the last gate diff would have been, when truncated
GATE_KEPT=0          # findings kept by the last filter_findings call
GATE_DROPPED=0       # findings dropped by the last filter_findings call

# Every file the driver or a stage writes at the worktree root for its
# own bookkeeping. One list: the gate-diff excludes derive from it, so a
# new bookkeeping file is added here and nowhere else. A reviewer
# reading PLAN.md checkboxes or the last TEST_OUTPUT.txt spends prefill
# on noise, and a per-file split must count only the task's files.
BOOKKEEPING_FILES=(
  .gitignore PLAN.md PLAN_INPUT.md HANDOFF.md NEXT_STEP.md TEST_OUTPUT.txt
  FINDINGS.md NEEDS_HUMAN.md
  "$(gate_output_file simplify)" "$(gate_output_file security)" "$(gate_output_file review)"
)
GATE_DIFF_EXCLUDES=()
for f in "${BOOKKEEPING_FILES[@]}"; do
  GATE_DIFF_EXCLUDES+=(":(exclude)$f")
done

# gate_diff [path]: the iteration's diff for the gates, bookkeeping
# files excluded, optionally narrowed to one path.
gate_diff() {
  if [ $# -gt 0 ]; then
    # :(literal) so a name starting with ':' or containing glob
    # characters is a path, never pathspec magic.
    git -C "$WORKTREE" diff "$ITER_BASE" HEAD -- ":(literal)$1" 2>&1
  else
    git -C "$WORKTREE" diff "$ITER_BASE" HEAD -- . "${GATE_DIFF_EXCLUDES[@]}" 2>&1
  fi
}

# is_no_findings_line <line>: the one test for a clean verdict, used
# both on a findings file and on a reply read back from a gate's log.
# Anchored on purpose. A substring test would read "this is NOT a no
# findings case" as a clean verdict, turning a gate that never answered
# into a pass. gate-rules.md asks for "no findings" plus a one-line
# reason, so the verdict opens the line.
is_no_findings_line() {
  local line="$1"
  # Strip an optional list marker and leading space.
  line="${line#"${line%%[![:space:]]*}"}"
  case "$line" in
    -\ *|\*\ *) line="${line#* }" ;;
  esac
  case "$line" in
    [Nn][Oo]\ [Ff][Ii][Nn][Dd][Ii][Nn][Gg][Ss]*) return 0 ;;
    *) return 1 ;;
  esac
}

# A cited path must stay inside the worktree and outside the driver's
# own state: no absolute path, no ".." segment, nothing under .loop-run/.
path_is_inside_worktree() {
  case "$1" in
    /*|.loop-run|.loop-run/*) return 1 ;;
  esac
  case "/$1/" in
    */../*) return 1 ;;
  esac
  return 0
}

# A finding line starts with an optional list marker, then path:LINE.
FINDING_RE='^[[:space:]]*(-|\*|[0-9]+\.)?[[:space:]]*`?([^[:space:]:`]+):([0-9]+)'

# filter_findings <gate>: mechanically checks the gate's output file and
# writes FINDINGS.md (what the fix stage reads). A line is kept only when
# it names a file that exists in the worktree; everything else -- prose,
# a hallucinated path, a "no findings" line from a per-file chunk -- goes
# to .loop-run/REJECTED_FINDINGS.md with the gate name. This is the free
# filter against invented defects; the model's judgment is never trusted
# to have cited a real file. Returns 0 when at least one finding is kept.
filter_findings() {
  local gate="$1" src="$WORKTREE/$(gate_output_file "$1")"
  local rejected="$WORKTREE/.loop-run/REJECTED_FINDINGS.md"
  local line path
  GATE_KEPT=0
  GATE_DROPPED=0
  # rm before the first write: the model can write anything in the
  # worktree, including a symlink at this name; never follow one.
  # REJECTED_FINDINGS.md accumulates across the run (cleared once at
  # setup), so a rejected line from an earlier gate stays on record.
  rm -f "$WORKTREE/FINDINGS.md"
  [ -L "$rejected" ] && rm -f "$rejected"
  : > "$WORKTREE/FINDINGS.md"
  if [ ! -s "$src" ]; then
    echo "no findings" > "$WORKTREE/FINDINGS.md"
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if [[ "$line" =~ $FINDING_RE ]]; then
      path="${BASH_REMATCH[2]}"
      # The model reads a plain git diff, so "b/src/x.py" is its most
      # likely spelling of "src/x.py".
      case "$path" in a/*|b/*) path="${path#?/}" ;; esac
      if path_is_inside_worktree "$path" && [ -f "$WORKTREE/$path" ]; then
        printf '%s\n' "$line" >> "$WORKTREE/FINDINGS.md"
        GATE_KEPT=$((GATE_KEPT + 1))
        continue
      fi
    else
      # A "no findings" line (from the gate, or from one per-file chunk)
      # is skipped only when the line is not a finding: a finding whose
      # sentence happens to contain the phrase is still a finding.
      is_no_findings_line "$line" && continue
    fi
    printf '%s: %s\n' "$gate" "$line" >> "$rejected"
    GATE_DROPPED=$((GATE_DROPPED + 1))
  done < "$src"
  if [ "$GATE_KEPT" -eq 0 ]; then
    echo "no findings" > "$WORKTREE/FINDINGS.md"
    return 1
  fi
  return 0
}

# recover_gate_verdict <gate> <out>: a gate that never called `write`
# but stated a parseable verdict in its reply has that verdict written
# to its findings file. The reply goes through the same rules the file
# would: a line starting path:LINE is a finding, a bare "no findings"
# line is a clean verdict, anything else is not an answer.
#
# This reads the answer the model gave; it does not take the model's
# word for anything the driver would not have taken from the file.
# filter_findings still checks every cited path afterwards.
recover_gate_verdict() {
  local gate="$1" out="$2" body kind line first
  [ -n "$LAST_STAGE_LOG" ] && [ -f "$LAST_STAGE_LOG" ] || return 1
  # Drop goose's banner, when there is one, and blank lines; keep what
  # the model said. The range delete is guarded: with no banner to match,
  # sed would delete the whole file.
  if grep -q 'goose is ready' "$LAST_STAGE_LOG" 2>/dev/null; then
    body="$(sed -e '1,/goose is ready/d' "$LAST_STAGE_LOG")"
  else
    body="$(cat "$LAST_STAGE_LOG")"
  fi
  body="$(printf '%s\n' "$body" | grep -v '^[[:space:]]*$')"
  [ -n "$body" ] || return 1
  # Does the reply contain an answer at all? Only that question is
  # decided here. What counts as a finding, and whether a cited path is
  # real, stays with filter_findings, the one place that judges content.
  kind=""
  first=true
  while IFS= read -r line; do
    if [[ "$line" =~ $FINDING_RE ]]; then kind=findings; break; fi
    # Only the opening line may carry a clean verdict: a reply that
    # discusses findings and mentions the phrase later is not clean.
    if $first && is_no_findings_line "$line"; then kind=clean; fi
    first=false
  done <<EOF
$body
EOF
  [ -n "$kind" ] || return 1
  unlink_if_symlink "$WORKTREE/$out"
  printf '%s\n' "$body" > "$WORKTREE/$out"
  GATE_RECOVERED="$gate"
  echo "run_loop.sh: gate '$gate' never called write; its $kind verdict was read from its reply" >&2
  return 0
}

# run_gate <gate>: runs one gate on the iteration's diff so far (from
# ITER_BASE to HEAD, so a gate also sees the fixes earlier gates caused).
# When the diff is over DIFF_SPLIT_BYTES and touches more than one file,
# the gate runs once per file on that file's diff alone and the outputs
# are concatenated. Returns 0 when findings remain after filtering, 1
# when none remain, 3 when the gate wrote no output file at all.
run_gate() {
  local gate="$1" out prompt files nfiles diff_bytes acc f
  out="$(gate_output_file "$gate")"
  prompt="$PROMPTS_DIR/$gate.md"
  local -a files
  local chunk_missing=false
  unlink_if_symlink "$WORKTREE/.loop-run/DIFF.txt"
  gate_diff > "$WORKTREE/.loop-run/DIFF.txt" || true
  diff_bytes="$(wc -c < "$WORKTREE/.loop-run/DIFF.txt" | tr -d ' ')"
  # NUL-separated names: with -z git prints every name literally, so a
  # non-ASCII or otherwise quotable name survives the round trip into
  # the per-file pathspec below.
  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(git -C "$WORKTREE" diff --name-only -z "$ITER_BASE" HEAD -- . "${GATE_DIFF_EXCLUDES[@]}" 2>/dev/null)
  nfiles="${#files[@]}"
  rm -f "$WORKTREE/$out"
  # DIFF.txt is rewritten on entry to every run_gate call, so after a
  # per-file split it is left holding the last file's diff on purpose.

  if [ "$diff_bytes" -gt "$DIFF_SPLIT_BYTES" ] && [ "$nfiles" -gt 1 ]; then
    echo "run_loop.sh: gate '$gate': diff is $diff_bytes bytes over $nfiles files (limit $DIFF_SPLIT_BYTES); running once per file" >&2
    acc="$WORKTREE/.loop-run/${gate}_chunks.md"
    rm -f "$acc"
    : > "$acc"
    for f in "${files[@]}"; do
      unlink_if_symlink "$WORKTREE/.loop-run/DIFF.txt"
      gate_diff "$f" > "$WORKTREE/.loop-run/DIFF.txt" || true
      rm -f "$WORKTREE/$out"
      stage_or_abort "$gate" "$prompt" "$out"
      if [ ! -f "$WORKTREE/$out" ] && ! $DRY_RUN; then
        # Per chunk, not after the loop: LAST_STAGE_LOG only ever holds
        # the most recent chunk's reply, and a merged $out exists as
        # soon as any one chunk succeeded.
        recover_gate_verdict "$gate" "$out" || true
      fi
      if [ -f "$WORKTREE/$out" ]; then
        { printf '## %s\n' "$f"; cat "$WORKTREE/$out"; echo; } >> "$acc"
      else
        # One unreviewed file fails the whole gate, same as the
        # unsplit path: never let a partial review pass as a full one.
        chunk_missing=true
        echo "run_loop.sh: gate '$gate' wrote no $out for $f" >&2
      fi
    done
    if [ -s "$acc" ]; then
      unlink_if_symlink "$WORKTREE/$out"
      cp "$acc" "$WORKTREE/$out"
    fi
  else
    stage_or_abort "$gate" "$prompt" "$out"
  fi

  if ! $DRY_RUN && [ ! -f "$WORKTREE/$out" ] && ! $chunk_missing; then
    # Last resort before failing closed: the model may have stated its
    # verdict in the reply instead of calling write.
    recover_gate_verdict "$gate" "$out" || true
  fi
  if ! $DRY_RUN && { [ ! -f "$WORKTREE/$out" ] || $chunk_missing; }; then
    return 3
  fi
  if filter_findings "$gate"; then
    return 0
  fi
  if [ "$GATE_RECOVERED" = "$gate" ] && [ "$GATE_KEPT" -eq 0 ] && [ "$GATE_DROPPED" -gt 0 ]; then
    # The reply looked like findings, but not one cited path survived.
    # That is a gate that did not review, not a gate that found nothing.
    echo "run_loop.sh: gate '$gate' was recovered from its reply but none of its $GATE_DROPPED cited path(s) exist; treating it as not run" >&2
    return 3
  fi
  return 1
}

# guard_deletes: called right after a fix stage's checkpoint commit. The
# model's judgment on deletes is the measured weak spot, so a fix commit
# that removes a file is reverted whole and the files are listed in
# NEEDS_HUMAN.md for a person to decide.
# guard_deletes <pre-fix commit>: compares that commit with the
# worktree's current tree (index and working files included), so a
# deletion is caught whether the model committed it, the checkpoint
# commit failed, or the model made extra commits of its own.
guard_deletes() {
  $DRY_RUN && return 0
  local pre="$1"
  local -a deleted
  local f n
  deleted=()
  git -C "$WORKTREE" add -A >/dev/null 2>&1 || true
  # --no-renames: a file the model moved is a delete plus an add here,
  # so a rename cannot slip past the guard as "R".
  while IFS= read -r -d '' f; do
    deleted+=("$f")
  done < <(git -C "$WORKTREE" diff --cached --no-renames --diff-filter=D --name-only -z "$pre" 2>/dev/null)
  [ "${#deleted[@]}" -gt 0 ] || return 0
  echo "run_loop.sh: WARNING fix stage deleted ${#deleted[@]} file(s); restoring them and leaving the decision to a human: ${deleted[*]}" >&2
  # Restore only the deleted paths, in a checkpoint of their own, so the
  # rest of the fix stage's work stays.
  for f in "${deleted[@]}"; do
    git -C "$WORKTREE" checkout "$pre" -- ":(literal)$f" >/dev/null 2>&1 \
      || echo "run_loop.sh: WARNING could not restore $f; inspect $WORKTREE by hand" >&2
  done
  unlink_if_symlink "$WORKTREE/NEEDS_HUMAN.md"
  {
    echo "## fix stage (step $STEP_N) deleted these files; the driver restored them"
    echo "A later fix stage must not delete them again. A human decides whether they go."
    printf -- '- %s\n' "${deleted[@]}"
  } >> "$WORKTREE/NEEDS_HUMAN.md"
  next_step_n; n="$STEP_N"
  STAGES_RUN+=("restore")
  commit_or_warn restore "$n"
  DELETES_REVERTED=$((DELETES_REVERTED + 1))
}

# run_fix_round: one fix stage on FINDINGS.md, the delete guard against
# the pre-fix commit, then the mechanical tests.
run_fix_round() {
  local pre
  pre="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || echo "$BASE_COMMIT")"
  stage_or_abort fix "$PROMPTS_DIR/fix.md"
  guard_deletes "$pre"
  run_test_stage
  LAST_TEST_RC=$?
}

# run_gates_for_iteration: passes over the gates in order until a pass
# lands no fix. A fix made for one gate is new code the other gates have
# not seen, so any fix restarts the pass; fix rounds per iteration are
# capped at GATE_ROUNDS across all gates, after which NOT_CONVERGED
# names the gate (or "tests") that still had something to fix. Tests
# that fail with no gate finding get a fix stage of their own inside
# the same cap, so that fix is gated too. Appends to GATES_FAILED when
# a gate writes nothing.
run_gates_for_iteration() {
  local gate grc rounds=0 pass_fixed
  while :; do
    pass_fixed=false
    if [ "${#GATES[@]}" -gt 0 ]; then
      for gate in "${GATES[@]}"; do
        run_gate "$gate"
        grc=$?
        if [ "$grc" -eq 3 ]; then
          echo "run_loop.sh: WARNING gate '$gate' produced no $(gate_output_file "$gate") -- the gate did not run; the loop cannot pass" >&2
          GATES_FAILED+=("$gate")
          GATE_LOG+=("iteration $ITER, gate $gate, round $rounds: no output (failed closed)")
          return 0
        fi
        GATE_LOG+=("iteration $ITER, gate $gate, round $rounds: $GATE_KEPT finding(s) kept, $GATE_DROPPED rejected$([ "$DIFF_TRUNCATED_TO" -gt 0 ] && echo ", diff truncated to $GATE_DIFF_BYTES of $DIFF_TRUNCATED_TO bytes")$([ "$GATE_RECOVERED" = "$gate" ] && echo ", verdict recovered from the reply")")
        GATE_RECOVERED=""
        if [ "$GATE_KEPT" -eq 0 ] && [ "$GATE_DROPPED" -gt 0 ]; then
          echo "run_loop.sh: gate '$gate' wrote $GATE_DROPPED line(s) the driver rejected and kept none; see .loop-run/REJECTED_FINDINGS.md" >&2
        fi
        [ "$grc" -eq 0 ] || continue
        if [ "$rounds" -ge "$GATE_ROUNDS" ]; then
          NOT_CONVERGED="$gate"
          echo "run_loop.sh: gate '$gate' still reports $GATE_KEPT finding(s) after $GATE_ROUNDS fix round(s); stopping as not converged -- see FINDINGS.md" >&2
          return 0
        fi
        rounds=$((rounds + 1))
        pass_fixed=true
        run_fix_round
      done
    fi
    if ! $pass_fixed && [ "$LAST_TEST_RC" -ne 0 ]; then
      if [ "$rounds" -ge "$GATE_ROUNDS" ]; then
        NOT_CONVERGED="tests"
        echo "run_loop.sh: tests still fail after $GATE_ROUNDS fix round(s); stopping as not converged -- see TEST_OUTPUT.txt" >&2
        return 0
      fi
      echo "run_loop.sh: tests fail with no gate finding to act on; running a fix stage on TEST_OUTPUT.txt" >&2
      rm -f "$WORKTREE/FINDINGS.md"
      echo "- TEST_OUTPUT.txt:1: the test command failed; read this output, find the cause in the code, and make the tests pass" > "$WORKTREE/FINDINGS.md"
      rounds=$((rounds + 1))
      pass_fixed=true
      run_fix_round
    fi
    $pass_fixed || return 0
  done
}

# abort_run <reason>: stop mid-run, leaving a summary that says why.
abort_run() {
  echo "run_loop.sh: aborting: $1" >&2
  unlink_if_symlink "$WORKTREE/LOOP_SUMMARY.md"
  {
    echo "# LOOP_SUMMARY (aborted)"
    echo
    echo "Repo: $REPO_PATH"
    echo "Worktree: $WORKTREE"
    echo "Branch: $BRANCH"
    echo "Aborted: $1"
    echo "Stages run: $STEP_N"
    echo "Stages: ${STAGES_RUN[*]:-none}"
  } > "$WORKTREE/LOOP_SUMMARY.md"
  exit 2
}

abort_misconfigured() {
  abort_run "endpoint misconfigured (Resource not found in a goose log under $LOG_DIR)"
}

finalize() {
  local final_test_rc="${1:-1}"
  local end_ts wall done_flag
  end_ts=$(date +%s)
  wall=$((end_ts - START_TS))
  if ! plan_has_unchecked && [ "$final_test_rc" -eq 0 ] \
     && [ -z "$NOT_CONVERGED" ] && [ "${#GATES_FAILED[@]}" -eq 0 ]; then
    done_flag=pass
  else
    done_flag=fail
  fi
  unlink_if_symlink "$WORKTREE/LOOP_SUMMARY.md"
  unlink_if_symlink "$WORKTREE/LOOP_DONE"
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
    echo "Gates: ${GATES[*]:-none}"
    echo "Gates with no output (failed closed): ${GATES_FAILED[*]:-none}"
    echo "Not converged: ${NOT_CONVERGED:-no}"
    echo "Fix stages that deleted files (restored): $DELETES_REVERTED$([ "$DELETES_REVERTED" -gt 0 ] && echo ' (see NEEDS_HUMAN.md)')"
    echo "Wall time: ${wall}s"
    echo
    echo "## Gate log"
    if [ "${#GATE_LOG[@]}" -gt 0 ]; then
      printf -- '- %s\n' "${GATE_LOG[@]}"
    else
      echo "- (no gate ran)"
    fi
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

stage_or_abort plan "$PROMPTS_DIR/plan.md" PLAN.md

# --------------------------------------------------------------------
# Loop: execute -> test -> gates (each gate: review, then fix + test
# while it reports findings, at most GATE_ROUNDS times), until PLAN.md
# has no unchecked steps and tests pass, or max-iterations is reached,
# or a gate does not converge.
# --------------------------------------------------------------------
while [ "$ITER" -lt "$MAX_ITERATIONS" ]; do
  ITER=$((ITER + 1))

  write_next_step

  stage_or_abort execute "$PROMPTS_DIR/execute.md"

  run_test_stage
  LAST_TEST_RC=$?

  # Each gate reads .loop-run/DIFF.txt, the delta since the last
  # iteration's gates finished (ITER_BASE), so a pass prefills only the
  # new work plus any fixes earlier gates in this iteration caused.
  # FULL_DIFF.txt keeps the whole run's diff for the summary. Both live
  # under .loop-run/ (gitignored), not the worktree root -- committing
  # DIFF.txt itself would make its own past content part of the next
  # iteration's diff.
  ITER_BASE="$(cat "$LAST_REVIEWED_FILE" 2>/dev/null || echo "$BASE_COMMIT")"
  unlink_if_symlink "$WORKTREE/.loop-run/FULL_DIFF.txt"
  git -C "$WORKTREE" diff "$BASE_COMMIT" HEAD > "$WORKTREE/.loop-run/FULL_DIFF.txt" 2>&1 || true

  run_gates_for_iteration

  unlink_if_symlink "$LAST_REVIEWED_FILE"
  git -C "$WORKTREE" rev-parse HEAD > "$LAST_REVIEWED_FILE"

  if [ -n "$NOT_CONVERGED" ] || [ "${#GATES_FAILED[@]}" -gt 0 ]; then
    # Neither can pass any more; spending further iterations only
    # gates later deltas while this one stays unreviewed.
    break
  fi
  if ! plan_has_unchecked && [ "$LAST_TEST_RC" -eq 0 ]; then
    break
  fi
done

finalize "$LAST_TEST_RC"
