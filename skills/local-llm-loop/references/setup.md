# Setup — server, endpoint, install

## Server-side prerequisites

Any OpenAI-compatible endpoint with tool calling works (llama-server,
vLLM, or another server exposing `/v1/chat/completions` with a
`tools`/`tool_calls` contract). If you're serving a small-active-parameter
MoE model on consumer hardware, four flags are worth setting deliberately
— each is cited against the benchmark that justifies it, by path in
`local-coding-env` (the repo this skill was measured against):

- **Expert-tensor offload for MoE.** Keeps prefill throughput in the
  usable range at the prompt sizes this loop's small-step discipline
  produces (`results/phase3/ladder-steps.csv`).
- **Full-precision (f16) KV cache, not quantized.** q8_0 KV scored lower
  on the accuracy suite *and* ran slower in the measured runs — quantizing
  KV cost both correctness and speed here (`results/phase3/suiteA/summary.csv`,
  compare `s4-qwopus-c65536-kvq8_0` against `kvf16`).
- **No speculative decoding.** It bought 15-19% faster wall time but
  dropped 1/25 on the accuracy suite, flipping the same task every run
  (`results/phase3/suiteA/summary.csv`, `s7-qwopus-spec1..4` vs `spec0`).
- **Micro-batch 512.** 1024 crashed the server outright with a CUDA
  illegal-memory-access (results/phase3/crashes/REPRO.md); even 768
  scored lower than 512 (`results/phase3/suiteA/summary.csv`,
  `iso-ub768-cache`).

Re-run your own tool-calling and accuracy suite before trusting these
flags on a different model family, quantization stack, or GPU — see
this skill's SKILL.md, "What would change this."

## Harness seam

`run_loop.sh` drives each stage through `LOOP_HARNESS_CMD`, a command
template with `{prompt}` substituted for that stage's prompt file.
Default:

```
LOOP_HARNESS_CMD="goose run --no-session -i {prompt}"
```

Goose is the shipped default and this loop is validated against it; the
`GOOSE_*` environment variables below are still exported to whatever
command `LOOP_HARNESS_CMD` names. Set `LOOP_HARNESS_CMD` to point the
loop at a different CLI harness that accepts a prompt file the same way
— for example another agent CLI with its own `--file`-style flag. The
template is parsed with normal shell word/quoting rules (not naive
whitespace splitting), so a quoted multi-word argument in the template
survives intact.

## Per-stage timeout

Each stage runs under `LOOP_STAGE_TIMEOUT` seconds (default 1800),
enforced by `timeout` if present, else `gtimeout`, else a `perl -e
'alarm ...'` fallback that ships with every macOS install and needs no
extra package. Stock macOS ships none of GNU `timeout`; installing
GNU coreutils is optional, only useful if you want `gtimeout` itself
rather than the bundled perl fallback:

```bash
brew install coreutils   # optional — provides gtimeout
```

## Gate diff splitting, fix-round cap, and gate bounds

`LOOP_DIFF_SPLIT_BYTES` (default 32768, about 8K tokens) sets the size
above which an iteration's diff, if it touches more than one file, is
split so each gate runs once per changed file on that file's diff
alone — no single prompt carries the whole diff.

`LOOP_GATE_ROUNDS` (default 2) caps the fix rounds allowed per gate per
iteration; a gate still reporting findings after that many rounds stops
the loop as "not converged".

`LOOP_MAX_TOKENS` (default 3072) is the output-token cap for the three
gate stages, sent to the harness as `GOOSE_MAX_TOKENS`. 3072 is the
benchmark's recommended client cap for tool-calling tasks
(`local-coding-env` REPORT.md). It bounds a runaway generation at the
server instead of waiting for the stage timeout: `GOOSE_MAX_TOKENS=48`
was verified live to truncate a 400-line answer to 7 lines.

`LOOP_STAGE_MAX_TOKENS` (default 8192) is the cap for the plan, execute
and fix stages, which write files. The benchmark measured 3072
truncating whole-file writes, so those stages get the larger cap. A call
cut at either cap is retried once: a gate is told to stop printing file
contents, a writing stage to split the write.

Both caps travel to the harness as `GOOSE_MAX_TOKENS`. A harness other
than Goose, set through `LOOP_HARNESS_CMD`, ignores that variable, so
only the stage timeouts bound it.

All four timeout and cap knobs (`LOOP_STAGE_TIMEOUT`, `LOOP_GATE_TIMEOUT`,
`LOOP_MAX_TOKENS`, `LOOP_STAGE_MAX_TOKENS`) must be integers of at least
1: 0 would disable a timeout and goose rejects a 0 cap.

`LOOP_GATE_TIMEOUT` (default 300 seconds) is the per-stage timeout for
the three gate stages, and is never set above `LOOP_STAGE_TIMEOUT`. A
gate writes at most ten lines, so a gate still running at this limit is
a runaway generation, not slow work.

## Gate config and the prompt-carried diff

A gate stage does not run under the same Goose config as plan, execute,
and fix. At run start, `run_loop.sh` derives `.loop-run/goose-config-gate/`
from the stage config by removing `shell`, `edit`, and `tree` from the
developer extension's `available_tools`, leaving `write` alone. The
driver exits with an error if `write` is not present in the result, so
a hand-edited stage config can't silently strip a gate down to nothing.

With no `shell` or `edit` tool, a gate has no way to read a file. The
diff under review, and the last 40 lines of `TEST_OUTPUT.txt`, are
appended to the gate's built prompt instead, under the headings "## The
diff under review" and "## Latest test run"; an empty diff is stated as
such rather than omitted. This removes the cause behind two failure
modes seen across live runs: a gate listing source into its reply until
the output cap or gate timeout cut it off, and a gate stating a correct
"no findings" verdict in prose without calling `write`. Both trace to
the gate having the `shell` tool; taking the tool away removes the
cause instead of adding more prompt wording.

## Installing Goose

Official installer:

```bash
curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | CONFIGURE=false bash
```

Or, on macOS with Homebrew:

```bash
brew install block-goose-cli
```

`CONFIGURE=false` / skipping `goose configure` matters: this skill's
config comes from `scripts/goose-config.example.yaml` plus environment
variables, not Goose's interactive setup wizard.

## Pointing Goose at your endpoint

Set three environment variables before running `scripts/run_loop.sh`
(see `scripts/env.example`):

```bash
export OPENAI_HOST=http://127.0.0.1:8080   # your server's base URL
export OPENAI_API_KEY=sk-local             # placeholder is fine if your server ignores it
export GOOSE_MODEL=your-model-name          # whatever your server expects in requests
```

`run_loop.sh` passes these to each `goose run` invocation directly on
the command's environment — never through a config file — so a stale
config can't silently override the endpoint you meant to hit.

To use the hardened tool config (recommended: cuts Goose's default
18-tool surface down to the 4 tools this loop was validated against),
point `XDG_CONFIG_HOME` at a directory holding a copy of
`scripts/goose-config.example.yaml` as `goose/config.yaml`:

```bash
mkdir -p ~/.config/local-llm-loop/goose
cp scripts/goose-config.example.yaml ~/.config/local-llm-loop/goose/config.yaml
export XDG_CONFIG_HOME=~/.config/local-llm-loop
```

If `XDG_CONFIG_HOME` is unset, `run_loop.sh` falls back to
`scripts/goose-config.example.yaml` directly, so the hardened config
still applies by default.

## Retry and prose-answer rules

- **HTTP 500 with a message like "does not match the expected ...
  format"** is the tool-call grammar rejecting a malformed call, not a
  crash. `run_loop.sh` retries that stage exactly once before moving on.
- **"Resource not found" (HTTP 404)** means the harness never reached
  the model — a wrong `OPENAI_HOST` or model name. `run_loop.sh` aborts
  the whole run immediately rather than burning iterations against a
  dead endpoint.
- **A prose answer, or a clarifying question, instead of a tool call**
  is a normal branch for this model class, not a bug — `tool_choice:
  "required"` has not been observed to guarantee a structured call on
  this stack. Don't build automation around that assumption; a stage
  that returns prose just leaves its output file unwritten, which the
  loop's fail-closed unchecked-step check already treats as "not done."
