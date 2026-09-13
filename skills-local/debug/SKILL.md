---
name: debug
description: Hypothesis-driven debugging — reproduce first, localize by bisection, test one hypothesis at a time, fix the cause not the symptom, prove the fix. Use whenever anything fails — bug report, failing test, error message, stack trace, regression, flaky behavior, or "it worked yesterday". Applies equally to failing builds, configs, queries, and pipelines. A red CI run starts with `ci-triage`.
---

<!-- local: derived-from: skills/debug/SKILL.md@ecfbd06382a9 -->

# Debug Protocol

You are a local model running inside Claude Code. The two ways your debugging fails: changing code before understanding the failure, and trying the same fix repeatedly. This protocol prevents both. Token usage is not a concern — thoroughness is.

## 0. Reproduce, or switch modes

Run the failing thing yourself. Record the exact command and the exact failing output. NO EDITS before you have a reproduction you can re-run on demand.
- Cannot reproduce (flaky, prod-only, "sometimes") → do not guess-fix. Collect evidence instead: logs, timestamps, inputs, environment; diff a failing instance against a succeeding one; add targeted logging at the suspected boundary and wait for the next occurrence. Flakiness is itself a diagnosis: suspect ordering, shared state, time, or concurrency.

## 1. Read the actual error

The whole message and the whole stack trace, from tool output — not from memory. The FIRST error in the output, not the last (later ones are cascade). Copy the key line verbatim into your notes.

## 2. State expected vs. observed

One line: "Expected A because <contract>; observed B." If you cannot state what should happen, investigate that first — you are not ready to debug.

## 3. Localize before theorizing

Shrink before theorizing, cheapest first:
1. Stack trace line → read that code.
2. `git diff` / `git log` against last-known-good — most bugs live in the most recent change. `git bisect` when the regression window is long.
3. Binary search: one print/log at the midpoint of the data flow — is the data still correct there? Halve and repeat.
4. Differential: find the closest working analog (passing sibling test, same call elsewhere) and minimize the difference.

## 4. Hypothesis loop

Each round, write exactly this before changing anything:
```
H<n>: cause=<one sentence> | test=<what you'll observe> | predict=<result if true>
```
Then: ONE change → run → record actual result → CONFIRMED or REFUTED.

HARD RULES:
- One hypothesis, one change, one observation per round. Never two changes at once.
- REVERT every refuted change immediately. Leftover edits poison later evidence.
- The same fix failing the same way twice = wrong hypothesis. NEVER try it a third time.
- After 3 refuted rounds: STOP. Re-read the code around the failure with no theory, build a smaller reproduction, and question one thing you assumed was fine (the input, the config, the test itself).

## 5. Fix the cause

Before writing the fix, state the chain: root cause → mechanism → observed failure. If you cannot explain the chain, you have not found the cause. FORBIDDEN fixes: widening a catch block, deleting the failing assert/test, adding sleep() to a race, hiding the error message.

## 6. Prove the fix

1. Re-run the original reproduction — quote the passing output verbatim.
2. Add a regression test and confirm it FAILS with the fix reverted (or clearly state why that check was impossible).
3. Run the neighboring tests — the fix must not break the callers.
4. Diff your final change: only the fix, no leftover prints or experiments.

Then finish with the `prove` skill's verification pass if the task is larger than the fix.

## Report format

Root cause (the chain, 1–2 sentences) → the fix → proof (quoted before/after output) → regression test added → "I verified …" / "I did not verify …". No narration of the journey.

## Anti-patterns

Each one lengthens the hunt.

- Editing before reproducing.
- Skimming the error and pattern-matching to a familiar bug ("probably a cache thing").
- Two changes per iteration.
- Making the error disappear instead of making the behavior correct — swallowing exceptions, deleting the failing assert, loosening the test.
- Blaming the compiler, framework, or library first — prove it with a minimal repro outside your code before you do.
- Leaving debug prints, commented-out experiments, or disabled tests in the final diff.
