---
name: apply-working-process
description: Loads the owner's standard working process (orchestrator-only role split, cheap-model implementation with fresh review tiered to what's being checked, board-as-plan issue discipline, red-first TDD, four gates before merge, effort-plan file, no decision log). Use when starting work in a repo, planning a feature, or before the first edit of a session in a project.
---

<!-- local: derived-from: skills/apply-working-process/SKILL.md@d61c70607769 -->
<!-- local: deliberate divergence: section 5 does not scale the simplify gate down on small diffs. That reduction exists only to save paid tokens, and local tokens are free, so the four simplify angles run on every diff regardless of size. -->
<!-- local: deliberate divergence: section 1's "token savings are an explicit owner directive" is inverted here — a free local model has no token budget to protect, so the directive becomes "spend tokens on thoroughness instead". -->

# Apply Working Process

You are working for the library's owner. Follow this process exactly. The visible process (red→green history, review gates, honest board and effort plan) IS the deliverable, not overhead. Token usage is not a concern here. Thoroughness is the priority, the opposite of the paid-tier discipline.

## 1. Roles and model routing

- Plan first, implement second, review third, never blended.
- If subagents exist: the orchestrator delegates and never edits files. Implementation runs on cheaper tiers. If not, do the phases yourself and review your own diff cold with the deep-review skill before committing.
- On a paid seat, token savings are an explicit owner directive. On a free local model there is no budget to protect, so spend freely on thoroughness. Never import the paid-tier lean discipline here.
- Apply `clean-code` while you write.
- When a named model is selected, use the newest version available in that tier and verify it is available. Never hardcode a stale version.
- A FRESH agent reviews every diff before it lands. FRESH applies at every tier. Match the tier to the check:
  - Haiku-tier for mechanical checks (orphaned imports, dead code after a deletion, deletion completeness, doc drift, test-count deltas, naming and style).
  - Sonnet-tier for ordinary correctness on contained diffs.
  - Top tier for adversarial passes on high-stakes paths: data that can be destroyed or corrupted, a security boundary, an assumption about an external system.
  - Do not spend the top tier on pattern-matching.
- The orchestrator runs on the seat's top tier. If that is the ordinary frontier tier, run it at high reasoning effort and say so, rather than silently downgrading.
- The local profile installs no playbooks. Apply the routing rule directly: judgment-heavy work goes to a paid tier. On a free local model, apply `quality`.

## 2. The plan lives on a board and in the effort plan

- Tasks are issues (`P<phase>.<seq>`) with labels for phase and implementation tier. The body carries: scope, a **Red-first** line (the failing artifact), **Done when** criteria, and a Definition-of-Done checklist.
- Issues stay the system of record. Planning documents freeze once imported to the board. The test plan stays a living document. The effort plan is the working copy for the current effort. A plan change lands in the issue first, then in the effort plan.
- The board NEVER lags reality. Work discovered mid-task gets an issue first, then a branch.
- Multi-step work keeps its live plan in `docs/CURR-AGENT-EFFORT.md` (create `docs/` if needed), updated BEFORE implementation, even when a board exists. Use the issue structure: scope, red-first, done when. The effort plan is not frozen. It is the only plan file that changes during the effort.

## 3. One issue = one branch = one PR

- Nothing reaches main without a PR. Every PR links its issue (`Closes #N`). A PR with no linked issue does not merge.
- Branches `feat/p<N>-<slug>` (or `fix/`, `docs/`, `ci/`). Conventional commits + `Assisted-by:` trailer. The pr-workflow skill owns PR craft once the branch exists.
- Run `ste-writing` on commit messages, PR titles, and PR descriptions. Where plain-language is installed, run it too. New prose has no em dashes.
- Code comments you add or change follow `ste-writing`. Do not rewrite unrelated comments.

## 4. Red first, strict TDD, everywhere

- Commit the failing artifact BEFORE implementing, visibly failing in PR history: unit test for logic, eval case for agent behavior, browser scenario for UI.
- Pair every mock-based test with a real-stack scenario.
- Model-inference evals never run in CI. Record locally, replay in CI.
- Do not relitigate the schedule cost. It is accepted.

## 5. Four gates before anything merges

- On the full PR diff, in order: simplify (declutter) → security review (sec-audit) → code review (deep-review) → clean-code review (clean-code skill as the lens; one single pass, no fan-out).
- Run the gates before the PR is created and again before any PR update that changes the diff. A description-only edit uses the prose checks in section 3 instead.
- Fix EVERY finding, no triaging into follow-ups, then re-run the full suite green. Docs PRs too. Fix-first beats ship-with-follow-up.
- Do NOT scale simplify down here. Run the four simplify angles (reuse, simplification, efficiency, altitude) on every diff regardless of size. Local tokens are free, so the paid-tier size exception does not travel.
- Security review and code review ALWAYS run at full strength regardless of diff size.
- Two review→fix rounds on one diff without convergence is the cap. Stop and surface to the owner with a recommendation rather than starting a third. Repeated rounds are evidence the approach is wrong, not that the fixes are nearly done.

## 6. Rationale goes where reviewers can see it

- Do not create a decisions log.
- Put needed rationale in an issue, the effort plan, a design document, or the PR.
- One-way-door architecture decisions get an ADR (via the paid-tier `architect` skill, not shipped in this pack).
- Never publish unverified vulnerability claims.

## 7. Working norms

- Anything that can be done now gets done now.
- Never game a metric. Non-deterministic failures stay xfail. Numbers report what happened.
- When an implementer's measurement against real data contradicts a reviewer's model of the risk, the measurement wins. Do NOT spend a review round fixing a finding the implementer already measured not to apply.
- In unattended runs: self-merge only after the gates pass. Leave owner-gated items open and annotated.
- Check in on long-running subagents every 15 minutes. Prefer a free spot-check (git status, docker ps, GPU/resource stats, artifact dirs) before spending a message on asking the agent. Read back actual output or status to confirm real progress, not just that they are alive. Interrupt and redirect stalled or looping work.
- The 15-minute spot-check includes CI. Is the task parked on a CI watch past the ceiling? (`gh run list` is free)
- CI watches are bounded. A hung run is a failure mode, not a long run. Derive the ceiling from the pipeline's known runtime (a suite that finishes in ~30 seconds gets a ~5-minute ceiling, not "until it ends"). Never watch unbounded.
- On breach, diagnose once: a run still queued never started, so cancel and re-run it once. A run genuinely executing gets one extension with a stated reason. Two strikes: surface to the owner instead of looping.
- Right after opening a PR, poll until checks exist (short loop, ~2-minute cap) before reading their absence as a verdict. "No checks reported" immediately post-push is usually the registration race, not the result.
- Brief subagents with the ceiling and re-run rule, not an open-ended `--watch`.
- Brief every subagent to NEVER end its turn to "wait" on a background, detached, or slow process. No wake-up notification arrives, so it would sleep forever. Poll inline in a bounded loop and keep going in the same turn instead.

## Adapting to a new environment

Map each element to what exists (which skills are the gates, board plus `docs/CURR-AGENT-EFFORT.md`, subagents vs phase separation). State the mapping once, then follow it. Do not silently drop the awkward parts. No subagents and only a local model: use `local-llm-loop`; its driver runs the simplify, security, and code-review gates as sequential fresh-process stages.
