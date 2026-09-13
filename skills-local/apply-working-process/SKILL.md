---
name: apply-working-process
description: Loads the owner's standard working process — orchestrator-only role split, cheap-model implementation with fresh review tiered to what's being checked, board-as-plan issue discipline, red-first TDD, three gates before merge, same-session decision logging. Use when starting work in a repo, planning a feature, or before the first edit of a session in a project.
---

# Apply Working Process

You are working for the library's owner. Follow this process exactly — the visible process (red→green history, review gates, honest board) IS the deliverable, not overhead.

## Step 1 — ROLES

Plan first, implement second, review third — never blended. If subagents exist: orchestrator delegates and never edits files; implementation on cheaper tiers; a FRESH agent reviews every diff before it lands, with the model tier matched to what is being checked: Haiku-tier for mechanical checks (orphaned imports, dead code after a deletion, deletion completeness, doc drift, test-count deltas, naming and style), Sonnet-tier for ordinary correctness on contained diffs, top tier for adversarial passes on high-stakes paths (anything that can destroy or corrupt user data, anything touching a security boundary, anything whose correctness rests on an assumption about an external system). FRESH applies at every tier; do not spend the top tier on pattern-matching. If not: do the phases yourself, and review your own diff cold with the deep-review skill before committing. The orchestrator runs on the seat's top tier. If the seat's top tier is the ordinary frontier tier, run it at high reasoning effort and say so, rather than silently downgrading. The local profile installs no playbooks, so apply the routing rule directly: judgment-heavy work goes to a paid tier; on a free local model, apply `quality`.

## Step 2 — THE PLAN LIVES ON A BOARD

Tasks are issues (`P<phase>.<seq>`) with: scope, a **Red-first** line (the failing artifact), **Done when** criteria, and a Definition-of-Done checklist. The board NEVER lags reality — work discovered mid-task gets an issue first, then a branch. No board? Keep `WORKPLAN.md` with the same structure.

## Step 3 — ONE ISSUE = ONE BRANCH = ONE PR

Nothing reaches main without a PR. Every PR links its issue (`Closes #N`). Branches `feat/p<N>-<slug>` (or `fix/`, `docs/`, `ci/`). Conventional commits + `Assisted-by:` trailer. The pr-workflow skill owns PR craft once the branch exists.

## Step 4 — RED FIRST, ALWAYS

Commit the failing artifact BEFORE implementing — visibly failing in PR history: unit test for logic, eval case for agent behavior, browser scenario for UI. Pair every mock-based test with a real-stack scenario. Model-inference evals never run in CI — record locally, replay in CI. Do not relitigate the schedule cost; it is accepted.

## Step 5 — THREE GATES BEFORE MERGE

On the full PR diff, in order: simplify (declutter) → security review (sec-audit) → code review (deep-review). Fix EVERY finding — no triaging into follow-ups — then re-run the full suite green. Docs PRs too. Fix-first beats ship-with-follow-up. Do NOT scale simplify down here — that reduction exists only to save paid tokens, and local tokens are free, so run all four angles (reuse, simplification, efficiency, altitude) on every diff regardless of size. (On paid tiers the canonical skill lets a small diff — under ~150 changed lines or one or two files, and not structurally significant — collapse into one combined pass, stated explicitly as a deviation; that allowance does not travel to free models.) Security review and code review ALWAYS run at full strength regardless of diff size. Two review→fix rounds on one diff without convergence is the cap — stop and surface to the owner with a recommendation rather than starting a third; repeated rounds are evidence the approach is wrong, not that the fixes are nearly done.

## Step 6 — LOG DECISIONS SAME-SESSION

Local gitignored `prd/DECISIONS.md`: every owner decision the session it's made, format `Decision / Alternatives rejected / Why`. Your own autonomous judgment calls get logged AND surfaced to the owner. Never publish strategy notes or unverified vulnerability claims.

## Step 7 — NORMS

Anything that can be done now gets done now. Never game a metric — non-deterministic failures stay xfail, numbers report what happened. When an implementer's measurement against real data contradicts a reviewer's model of the risk, the measurement wins — do NOT spend a review round fixing a finding the implementer already measured not to apply. In unattended runs: self-merge only after gates pass; leave owner-gated items open+annotated. Check in on long-running subagents every 15 minutes — prefer a free spot-check (git status, docker ps, GPU/resource stats, artifact dirs) before spending a message on asking the agent; read back actual output/status to confirm real progress, not just that they're alive; interrupt and redirect stalled or looping work. CI watches are bounded — a hung run is a failure mode, not a long run: derive the ceiling from the pipeline's known runtime (a suite that finishes in ~30 seconds gets a ~5-minute ceiling, not "until it ends"); never watch unbounded. On breach, diagnose once: a run still queued never started — cancel and re-run it once; a run genuinely executing gets one extension with a stated reason. Two strikes → surface to the owner instead of looping. Right after opening a PR, poll until checks exist (short loop, ~2-minute cap) before reading their absence as a verdict — "no checks reported" immediately post-push is usually the registration race, not the result. Brief subagents with the ceiling/re-run rule, not an open-ended `--watch`; and the 15-minute spot-check of a delegated task includes "is it parked on a CI watch past the ceiling?" (`gh run list` is free). Brief every subagent to NEVER end its turn to "wait" on a background/detached/slow process (no wake-up notification arrives — it would sleep forever); poll inline in a bounded loop and keep going in the same turn instead.

## FIRST USE IN A NEW ENVIRONMENT

Map each element to what exists (which skills are the gates, board vs WORKPLAN.md, subagents vs phase separation). State the mapping once, then follow it. Do not silently drop the awkward parts.
