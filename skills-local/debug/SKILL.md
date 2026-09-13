---
name: debug
description: Hypothesis-driven debugging — reproduce first, localize by bisection, test one hypothesis at a time, fix the cause not the symptom, prove the fix. Use whenever anything fails — bug report, failing test, error message, stack trace, regression, flaky behavior, or "it worked yesterday". Applies equally to failing builds, configs, queries, and pipelines. A red CI run starts with `ci-triage`.
---

# Debug Protocol

You are a local model running inside Claude Code. The two ways your debugging fails: changing code before understanding the failure, and trying the same fix repeatedly. This protocol prevents both. Token usage is not a concern — thoroughness is.

## Step 1 — REPRODUCE

Run the failing thing yourself. Record the exact command and the exact failing output. NO EDITS before you have a reproduction you can re-run on demand.
- Cannot reproduce → do not guess-fix. Collect evidence instead: logs, inputs, environment; diff a failing instance against a succeeding one; report what you find.

## Step 2 — READ THE ERROR

The whole message and the whole stack trace, from tool output — not from memory. The FIRST error in the output, not the last (later ones are cascade). Copy the key line verbatim into your notes.

## Step 3 — STATE THE GAP

One line: "Expected A because <contract>; observed B." If you cannot state what should happen, investigate that first — you are not ready to debug.

## Step 4 — LOCALIZE

Shrink before theorizing, cheapest first:
1. Stack trace line → read that code.
2. `git diff` / `git log` — most bugs live in the most recent change.
3. Binary search: one print/log at the midpoint of the data flow — is the data still correct there? Halve and repeat.
4. Differential: find the closest working analog (passing sibling test, same call elsewhere) and minimize the difference.

## Step 5 — HYPOTHESIS LOOP (max 3 rounds)

Each round, write exactly this before changing anything:
```
H<n>: cause=<one sentence> | test=<what you'll observe> | predict=<result if true>
```
Then: ONE change → run → record actual result → CONFIRMED or REFUTED.

HARD RULES:
- One hypothesis, one change, one observation per round. Never two changes at once.
- REVERT every refuted change immediately. Leftover edits poison later evidence.
- The same fix failing the same way twice = wrong hypothesis. NEVER try it a third time.
- After 3 refuted rounds: STOP. Re-read the code around the failure with no theory, build a smaller reproduction, and question one thing you assumed was fine (the input, the config, the test itself). Then report state honestly if still stuck.

## Step 6 — FIX THE CAUSE

Before writing the fix, state the chain: root cause → mechanism → observed failure. If you cannot explain the chain, you have not found the cause. FORBIDDEN fixes: widening a catch block, deleting the failing assert/test, adding sleep() to a race, hiding the error message.

## Step 7 — PROVE IT

1. Re-run the original reproduction — quote the passing output verbatim.
2. Add a regression test and confirm it FAILS with the fix reverted (or clearly state why that check was impossible).
3. Run the neighboring tests — the fix must not break the callers.
4. Diff your final change: only the fix, no leftover prints or experiments.

## Report

Root cause (the chain, 1–2 sentences) → the fix → proof (quoted before/after output) → regression test added → "I verified …" / "I did not verify …". No narration of the journey.
