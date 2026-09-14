---
name: local-llm-loop
description: "Runs the working loop for a coding agent backed by a local, small-active-parameter model (~3B active MoE) on consumer hardware — short steps, a mechanical check after every write, tolerant of format-rejection retries and prose-instead-of-a-call. Use when Claude Code or any agent runs against a local server (ANTHROPIC_BASE_URL, llama.cpp, Ollama, LM Studio), or when tuning that server's inference flags."
---

# Local LLM Loop

A local ~3B-active model is reliable at small, checked steps and unreliable at one long unsupervised generation — this is a measured property of the model class, not a style preference. `local-coding-env` (`results/`) is the benchmark repo behind every rule below; each rule cites the file that justifies it. The headline contrast: 3,718 of 3,718 tool calls valid across 69 runs and 27 configurations at small granularity (`results/phase4/corpus_validity.json`), against a ~5,600-token one-shot game that fails to parse in 3 of 3 byte-identical runs (`results/phase5/suiteB/summary.csv`, config `p5b-qwopus-final`; `results/phase5/suiteB/p5b-qwopus-final/run1/mechanical.json`). The loop below keeps the agent inside the region the model is actually reliable in, and puts the recovering in the harness, not the weights.

**Prerequisites:** an OpenAI-compatible endpoint with tool calling (llama-server or similar), Goose CLI, and `OPENAI_HOST`/`OPENAI_API_KEY`/`GOOSE_MODEL` set. See `references/setup.md` for server flags, the install line, and the endpoint env vars.

## Run it

```bash
export OPENAI_HOST=http://127.0.0.1:8080
export OPENAI_API_KEY=sk-local
export GOOSE_MODEL=your-model-name

bash scripts/run_loop.sh <repo> plan.md --test-cmd "python3 -m unittest discover -s tests -t ."
```

`run_loop.sh` drives Goose through a fresh-context plan stage, then
execute/test/review/fix cycles, each stage checkpointed with its own
commit on a disposable git worktree branch at
`<repo>/.loop/<timestamp>/`. Inside that worktree: `PLAN.md` (the step
checklist), `HANDOFF.md` (updated every stage), `DIFF.txt` and
`REVIEW.md` (each iteration's review pass), `TEST_OUTPUT.txt`, and on
completion `LOOP_SUMMARY.md` plus a `LOOP_DONE` marker. Run
`bash scripts/run_loop.sh <repo> plan.md --dry-run` first — it exercises
the worktree, prompts, and mechanical test stage for real without
calling the model, so plumbing problems surface before spending an
iteration budget. `bash scripts/test_loop.sh` runs the driver's own test
suite (no live model needed).

`<repo>/.loop/` is created inside the target repo's own working tree and
is never added to that repo's top-level `.gitignore` automatically — add
`.loop/` to `<repo>/.gitignore` yourself, or delete `.loop/<timestamp>/`
worktrees by hand (`git -C <repo> worktree remove .loop/<timestamp>`)
once you're done with a run, so `git status` in `<repo>` stays clean.

## The loop

1. **Plan into steps, not one shot.** Break the task into steps a plan can state in under ~500–700 output tokens, one file (or one focused change) per turn — never "generate the whole thing." *Why:* prefill is the cost that scales with prompt/plan size on this hardware (`results/phase3/ladder-steps.csv`, `s2` rows: 2K prefill runs 400–680 tok/s at the shipped setting), so a long plan or a long single-shot generation both spend tokens in the model's unreliable regime; the one 5,600-token single-file game judged 18/20 on source but shipped a fatal duplicate declaration (`Identifier 'alienShootTimer' has already been declared`) with zero executable features, identically in all 3 runs (`results/phase5/suiteB/p5b-qwopus-final/run1/judge.json`, its `note` field).

2. **Check mechanically after every write, before the next step.** Parse it, load it, look for console errors — before starting the next file or step. *Why:* the agentic loop that adds this check went 6/6 with no console errors across three runs (`results/phase5/suiteB-agentic/run1/mechanical.json`, `run2/mechanical.json`, `run3/mechanical.json`), against the same task's 0/3 one-shot (`results/phase5/suiteB/summary.csv`).

3. **Never chain a second write ahead of the first write's check.** Don't queue write N+1 before write N's mechanical check has actually returned — a check that runs after the fact doesn't localize which write broke things. *Why:* same evidence as step 2 — the 6/6 result depends on the check gating the next step, not running after several writes have already landed.

4. **Keep tool calls small.** Don't design a tool schema, or a task, that needs one huge call; the largest single tool call proven to work is ~700 tokens. *Why:* `results/phase4/token_budget.json`, `max_tool_call_observed` = 694.6 tokens (`write_file`, config `s1-gptoss-ncmoe16`); the full 3,718-call corpus at that granularity had zero invalid calls across 27 configurations (`results/phase4/corpus_validity.json`), and the deterministic three-run combined-flags suite scored 25/25 (`results/phase3/suiteA/summary.csv`, config `final-qwopus-combined`).

5. **Retry on HTTP 500 — that's the format-rejection path, not a crash.** When the constrained decoder (the tool-call grammar) refuses a malformed call, the server returns an HTTP 500 with a message like `"The model produced output that does not match the expected peg-native format"`, not a normal chat completion. The harness must retry the step. *Why:* `results/phase4/grammar_proof.json`, probe `a_required_malformed` (`http_error: "HTTP 500"`) and its `verdict.harness_implication`.

6. **Treat a prose answer, or a question back, as a normal branch — not a bug.** Don't build the loop assuming `tool_choice: "required"` guarantees a structured call, and don't treat a clarifying question as a failure to route. *Why:* `results/phase4/grammar_proof.json`, `verdict.tool_choice_required_enforced` is `null` because the enforcing probe errored before producing a message, and an earlier unconstrained control probe returned plain prose (`<tool_code>read_file("README.md")`) instead of a `tool_calls` entry (same file, `a_control_unconstrained`; corroborated in `REPORT.md:439`).

7. **Expect recovery behavior to differ by model — don't assume one recovery style.** Given a missing file at a hinted-wrong path, one model asks and stops; another keeps exploring toward the right name. *Why:* Qwen3.6 tries once, lists the directory, and gives up ("I cannot determine the port from it," `results/phase2/shakedown/suiteA/shakedown-qwen36-think/run1/rc1_wrong_path_hint.json`), while Qwopus keeps exploring toward `config/settings.yaml` (`results/phase3/suiteA/final-qwopus-combined/run1/rc1_wrong_path_hint.json`); aggregate pass medians in `results/phase3/step1_rescored.csv`.

8. **Prefer accuracy settings over speed settings.** Don't tune flags for tokens/sec alone. *Why*, three measured cases in `results/phase3/suiteA/summary.csv`: speculative decoding (`s7-qwopus-spec1..4`) scores 24/25, flipping the same task (`sp2_delete_trap`) every run, against `spec0`'s 25/25 (REPORT.md, lines 264-265), despite 15–19% faster wall time (spec0 median 241.6s vs spec1–4 medians 198–206s); q8_0 KV cache (`s4-qwopus-c65536-kvq8_0`) scores 23/25 and is *slower* than f16 KV's 25/25 (`kvf16` run1 238.5s vs `kvq8_0` run1 290.3s); micro-batch 1024 crashes the server outright with a CUDA illegal-memory-access (results/phase3/crashes/REPRO.md), and even 768 only reaches 23/25 (`iso-ub768-cache` row).

9. **Keep the harness light and the tool count small.** Since prefill scales with what's in the prompt (step 1's citation), fewer tool definitions and a shorter system prompt buy back exactly the prefill budget the loop needs for small, checked steps. *Why:* results/phase5/harness-install.md (the harness install/config notes this loop was validated against).

10. **Run the tool-calling suite as the regression gate whenever the model or the inference build changes.** *Why:* REPORT.md, section 18 ("What to re-test when llama.cpp or the model changes") — re-run Suite A x3 on the shipped flags and compare the median against `results/phase3/suiteA/summary.csv`; a drop blocks the change. Re-run `corpus_validity.py` and `grammar_proof.py` alongside it — both must still show the 1.0 valid-call rate.

11. **Use determinism to catch drift for free.** At temperature 0, identical configs reproduce identical token counts and, in the one-shot case, byte-identical output — `tokens_total` is exactly 39232 across all three `final-qwopus-combined` runs and exactly 39213 across all three `s7-qwopus-spec1` runs (`results/phase3/suiteA/summary.csv`); the one-shot game's `html_sha256` is identical across all 3 runs (`results/phase5/suiteB/summary.csv`). An unexpected change in either, at the same config, means the build or the model changed underneath you — treat it as a signal, not noise.

## Anti-patterns

- **One-shot file generation** — "write the whole game/module/service in one call." The one measured attempt at this scored 18/20 on source and 0 executable features, identically, three times (step 1's citation).
- **Trusting speed settings** — picking speculative decoding, quantized KV cache, or a large micro-batch because the benchmark number is bigger, without re-running the accuracy suite. All three measured cases traded correctness for speed, and one of them crashes the server (step 8's citation).
- **Relying on `tool_choice: "required"`** to skip the "what if it doesn't call a tool" branch. It has not been observed enforced on this stack, and an unconstrained control run produced prose instead of a call (step 6's citation).
- **Tuning from blog posts or vendor defaults** instead of this repo's own suite. A flag that helps someone else's model/hardware/task mix is not evidence for this one; every number above came from a controlled comparison run on this exact model and machine.

## What would change this

Every rule here was measured on one model family (a Qwen3.6-class MoE, ~3B active parameters, exposed as "Qwopus" in the benchmark repo) on one laptop (results/phase3/crashes/REPRO.md: RTX 5060 Laptop, 8 GB VRAM). A different active-parameter count, a different MoE routing design, a different quantization stack, or different VRAM headroom could shift where the reliable-step-size boundary sits, whether speculative decoding stays accuracy-negative, or whether the format-rejection-as-HTTP-500 behavior even holds. Re-run the suites named in step 10 on the new stack before trusting these thresholds elsewhere; don't port the numbers, port the method.
