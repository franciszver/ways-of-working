---
name: apply-working-process
description: Load the owner's standard working process — role split, board-as-plan, red-first TDD, three gates, same-session decision logging. Use at the start of any project session so you work the way the owner works.
---

# Apply Working Process

You are working for the library's owner. Follow this process exactly — the visible process (red→green history, review gates, honest board) IS the deliverable, not overhead.

## Step 1 — ROLES

Plan first, implement second, review third — never blended. If subagents exist: orchestrator delegates and never edits files; implementation on cheaper tiers; a FRESH agent on an equal-or-better model reviews every diff before it lands. If not: do the phases yourself, and review your own diff cold with the deep-review skill before committing. The orchestrator itself runs on Fable-tier by default; no Fable access → offer to switch the orchestrator to Opus at high reasoning effort instead of silently downgrading. The fable-quality-library ROUTING playbook governs tier selection.

## Step 2 — THE PLAN LIVES ON A BOARD

Tasks are issues (`P<phase>.<seq>`) with: scope, a **Red-first** line (the failing artifact), **Done when** criteria, and a Definition-of-Done checklist. The board NEVER lags reality — work discovered mid-task gets an issue first, then a branch. No board? Keep `WORKPLAN.md` with the same structure.

## Step 3 — ONE ISSUE = ONE BRANCH = ONE PR

Nothing reaches main without a PR. Every PR links its issue (`Closes #N`). Branches `feat/p<N>-<slug>` (or `fix/`, `docs/`, `ci/`). Conventional commits + `Assisted-by:` trailer. The pr-workflow skill owns PR craft once the branch exists.

## Step 4 — RED FIRST, ALWAYS

Commit the failing artifact BEFORE implementing — visibly failing in PR history: unit test for logic, eval case for agent behavior, browser scenario for UI. Pair every mock-based test with a real-stack scenario. Model-inference evals never run in CI — record locally, replay in CI. Do not relitigate the schedule cost; it is accepted.

## Step 5 — THREE GATES BEFORE MERGE

On the full PR diff, in order: simplify (declutter) → security review (sec-audit) → code review (deep-review). Fix EVERY finding — no triaging into follow-ups — then re-run the full suite green. Docs PRs too. Fix-first beats ship-with-follow-up.

## Step 6 — LOG DECISIONS SAME-SESSION

Local gitignored `prd/DECISIONS.md`: every owner decision the session it's made, format `Decision / Alternatives rejected / Why`. Your own autonomous judgment calls get logged AND surfaced to the owner. Never publish strategy notes or unverified vulnerability claims.

## Step 7 — NORMS

Anything that can be done now gets done now. Never game a metric — non-deterministic failures stay xfail, numbers report what happened. In unattended runs: self-merge only after gates pass; leave owner-gated items open+annotated. Check in on long-running subagents every 15 minutes — prefer a free spot-check (git status, docker ps, GPU/resource stats, artifact dirs) before spending a message on asking the agent; read back actual output/status to confirm real progress, not just that they're alive; interrupt and redirect stalled or looping work. Brief every subagent to NEVER end its turn to "wait" on a background/detached/slow process (no wake-up notification arrives — it would sleep forever); poll inline in a bounded loop and keep going in the same turn instead.

## FIRST USE IN A NEW ENVIRONMENT

Map each element to what exists (which skills are the gates, board vs WORKPLAN.md, subagents vs phase separation). State the mapping once, then follow it. Do not silently drop the awkward parts.
