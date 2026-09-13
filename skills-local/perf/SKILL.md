---
name: perf
description: Measurement-driven performance work — profile first, fix the top bottleneck only, re-measure, stop at the target. Use when something is slow, memory-heavy, or expensive, or when asked to optimize.
---

<!-- local: derived-from: skills/perf/SKILL.md@6f8daf010522 -->

# Perf Protocol

You are a local model doing performance work. Token usage is not a concern, but code changes without measurements are forbidden — intuition about where time goes is usually wrong.

## Step 1 — TARGET

Write a numeric target before touching anything ("p95 < 200ms", "run completes < 10 min"). No target from the user → propose one and confirm. Record the workload/conditions it applies to. No target = no stopping rule = wasted work.

## Step 2 — BASELINE

Reproduce the slowness on demand and record the number. Benchmark hygiene, mandatory: warm up first · run at least 3 times · report median and spread, never the best run · same data, same flags, same machine for every comparison.

## Step 3 — PROFILE

Find where time/memory actually goes: profiler if available, else timing probes at midpoints of the flow (bisect like debugging). Output = ranked list of costs. Suspect while profiling, never instead of it: N+1 queries · work hoistable out of loops · missing index · sync I/O on hot path · repeated recomputation · accidental O(n²) · unbatched round-trips.

## Step 4 — FIX THE TOP ITEM ONLY

One change per iteration. Preference order:
1. Don't do the work (cache an invariant, dedupe, early-exit, lazy)
2. Do less work (better algorithm/structure, batch, index, stream)
3. Do it faster (parallelism, low-level rewrite) — last resort, highest complexity cost

## Step 5 — RE-MEASURE AND DECIDE

Same benchmark, same conditions. Quote before and after numbers verbatim.
- Target met → STOP. Further optimization is unrequested complexity.
- Improved but short → back to Step 3; the profile has changed.
- No improvement → REVERT the change, re-read the profile. Never keep a change that didn't measurably help.

Run the test suite after every kept change — behavior must survive.

## Report

Target · baseline (quoted) · profile top items · change made · after number (quoted) · target met or remaining gap. Note any staleness/complexity a cache introduced. Leave the benchmark script in the repo if feasible.

## Hard rules

- Never optimize from how the code looks.
- Never add a cache without a profile justifying it and an invalidation story.
- Never trade correctness for speed silently — approximations and staleness windows get surfaced to the user.
- A path the profile shows at 2% has a 2% ceiling — skip it.
