---
name: ci-triage
description: Gets a red build green for the right reason — reads the first real failure, classifies it (code, test, flake, infra, drift), reproduces locally, fixes or quarantines with a ticket, never retries-until-green as a fix. Use when CI fails, a pipeline breaks, a build goes red, or a test is flaky. A local failure goes to `debug`.
---

# CI Triage Protocol

You are a local model fixing a red build. Token usage is not a concern — read the full CI log. Rerunning until green is forbidden; it converts bugs and flakes into a permanent tax.

## Step 1 — READ

GET THE LOG FIRST: `gh run list --limit 5` to find the run, then `gh run view <id> --log-failed` for only the failed steps. Find the FIRST failure in the run, not the last (later failures are cascade). Read the actual failing output, not the step name; copy the decisive line verbatim into your notes. List what changed since the last green run: the diff, but also dependencies, base images, runners — "no code changed" never means "nothing changed".

## Step 2 — CLASSIFY

Allowed diagnostic rerun: exactly ONE, same commit, only if unsure. Same failure → deterministic. Different/gone → flake or infra. Then classify:

- CODE BUG: fails deterministically, traceable to the diff → fix via the debug skill
- BROKEN TEST: code is right, expectation stale → fix the test, but PROVE the code is right first
- FLAKE: same commit passes and fails → quarantine + ticket (Step 4), never shrug-rerun
- INFRA: runner died, disk full, registry timeout, no test output → rerun is legitimate for this class only; recurring → escalate
- DRIFT: a dependency/tool/image resolved to a new version → pin it now, upgrade deliberately later

## Step 3 — REPRODUCE AND FIX

Run the failing thing locally with the command CI ran (read it from the workflow file). Local passes but CI fails → diff the environments (versions, env vars, parallelism, timezone, test order) — that diff is the bug's habitat. Prove the fix like debug does: the failing run now passes, quoted.

## Step 4 — FLAKES

A flake is a real bug (shared state, order dependence, time, unawaited async, port collision).
1. Stress-run the single test if cheap (--repeat).
2. Root-cause fixable now → fix it.
3. Else quarantine: skip WITH a ticket linked in the skip marker. A skip without a ticket is a deletion.
4. Never "fix" with sleeps or wider timeouts.

## Step 5 — WHEN MAIN IS RED

Fix forward only if minutes away; otherwise revert the breaking change first. Many entangled commits → git bisect with the CI command; do not guess. Never debug by pushing guess-commits — every push costs the whole queue.

## Report

Classification (evidence line quoted) · root cause or quarantine ticket · fix + local verification (quoted) · can it recur, and what would prevent it. If infra: say so explicitly.
