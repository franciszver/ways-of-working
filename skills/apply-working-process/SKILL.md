---
name: apply-working-process
description: Loads the owner's standard working process (orchestrator-only role split, cheap-model implementation with fresh review tiered to what's being checked, board-as-plan issue discipline, red-first TDD, four gates before merge, effort-plan file, no decision log). Use when starting work in a repo, planning a feature, or before the first edit of a session in a project.
---

# Apply Working Process

This is how the library's owner runs engineering work. It was proven on the AgentForge series (a multi-phase portfolio build) and applies to any project unless they say otherwise. The principle underneath all of it: **the visible process is itself the evidence of quality**: red→green history, review gates, and an honest board and effort plan are the deliverable, not overhead.

## 1. Roles and model routing

- **The orchestrator plans, sequences, delegates, reviews, and merges — it never edits files directly.**
- Implementation runs on cheaper models: Sonnet-tier for all real work, Haiku-tier only for pure boilerplate (scaffolding, fixtures, config). Token savings are an explicit owner directive, not an optimization to debate.
- Implementers apply `clean-code` while they write, not only in review.
- When a named model is selected, use the newest version available in that tier. Verify that it is available. Never hardcode a stale version.
- **Every diff is reviewed by a fresh agent — model tier follows what the check is verifying, not the fact that it's a review.** "Fresh" (no implementation context, so it can't inherit the implementer's blind spots) applies at every tier below:
  - Haiku-tier for mechanical/structural checks with a checkable right answer: orphaned imports and dead code after a deletion, deletion completeness (no dangling references), stale comments and doc drift, test-count deltas, naming and style consistency.
  - Sonnet-tier for ordinary correctness review on contained diffs.
  - Opus-tier (or the strongest available) for adversarial passes on high-stakes paths: anything that can destroy or corrupt user data, anything touching security boundaries, anything whose correctness depends on an assumption about an external system (hardware, a device protocol, a third-party API). Its use is called out explicitly.
- Don't spend the expensive tier on pattern-matching work — routing an import check to a top-tier model buys nothing a cheap tier plus verification wouldn't also catch.
- No subagents in this environment? Keep the *phase separation*: plan first, implement second, then review your own diff cold with `deep-review` before committing.
- The orchestrator runs on the seat's top tier. If the seat's top tier is the ordinary frontier tier, run it at high reasoning effort and say so, rather than silently downgrading.
- The full model-selection judgment lives in the ROUTING playbook installed beside these skills: `~/.claude/playbooks/ROUTING.md` for a user install, `.claude/playbooks/ROUTING.md` for a project install. This section is its standing application; ROUTING.md wins if they drift.

## 2. The plan lives on a board and in the effort plan

- A public GitHub Project (or the environment's equivalent) is the **live operational plan**: phases → milestones, tasks → issues titled `P<phase>.<seq>`, labels for phase and implementation tier.
- Each issue body carries: scope, a **Red-first** line (the failing artifact to write before implementing), **Done when** (acceptance criteria), and the Definition-of-Done checklist.
- Issues stay the system of record. Planning documents freeze once imported to the board, and the effort plan is the working copy for the current effort. A plan change lands in the issue first, then in the effort plan. (Exception: the test plan stays a living document.)
- **The board never lags reality.** Work discovered mid-task gets an issue created *first*, with acceptance criteria, then a branch.
- **Multi-step work keeps its live plan in `docs/CURR-AGENT-EFFORT.md`.** Create `docs/` if needed. Update the file before implementation starts, even when a project board also tracks the work. Use the issue structure: scope, red-first, done when. The effort plan is not frozen. It is the only plan file that changes during the effort.

## 3. One issue = one branch = one PR

- Nothing reaches `main` without a feature branch and a PR. No direct pushes, no "quick fixes."
- Every PR links its issue via `Closes #N`; a PR with no linked issue does not merge.
- Branches: `feat/p<N>-<slug>` (or `fix/`, `docs/`, `ci/`). Conventional commits, with an `Assisted-by: <tool>` trailer when an AI helped.
- Once the branch exists, `pr-workflow` owns the craft: commit narrative, PR description, review dialogue.
- **Prose checks.** Run `plain-language` and `ste-writing` on commit messages, PR titles, and PR descriptions. New prose has no em dashes (see `plain-language`).
- **Code comments** that you add or change follow `ste-writing`. Do not rewrite unrelated comments.

## 4. Red first — strict TDD, everywhere

- The failing artifact is committed and **visibly failing in PR history** before implementation: unit test for logic, eval case for agent behavior, browser scenario for UI flows.
- Every mock-based test of an external system is paired with a scenario against the real running stack — mocks mirror assumptions; scenarios check them.
- Model-inference evals never run in CI: live runs happen locally and record outputs; CI replays recordings through deterministic assertions.
- This is a conscious owner override of hybrid approaches — the ~20–30% schedule cost is accepted for uniform "no untested line" discipline. Don't relitigate it.

## 5. Four gates before anything merges

- On the full PR diff, in order: **simplify → security review → code review → clean-code review** (in Claude Code: `/simplify` → `/security-review` → `/code-review` → the `clean-code` skill as the review lens; elsewhere use this library's `declutter`, `sec-audit`, `deep-review`, `clean-code`).
- Run the gates before the PR is created and again before any PR update that changes the diff. A description-only edit uses the prose checks in §3 instead.
- Every finding fixed, not triaged into follow-ups, and the full test suite re-run green *after* the fixes. Applies to docs PRs too.
- When a gate finds a real defect, **fix-first beats ship-with-follow-up**, even if the reviewer says shipping is acceptable.
- **Scale the simplify gate's fan-out to the diff. Security review and code review always run at full strength regardless of size.** Simplify normally fans out to the four simplify angles in parallel (reuse, simplification, efficiency, altitude). On a small diff (roughly under ~150 changed lines, or confined to one or two files) collapse that to a single combined pass covering every angle, on a cheap tier. Larger or structurally significant diffs keep the full parallel fan-out. Structural significance overrides the size heuristic, so a large single-file rewrite is not a small diff. State explicitly when the reduced form is used, so a reduced gate is never mistaken for a full one. This rule applies to simplify only, never to security review or code review, which are the gates that catch defects.
- The clean-code review is always a single pass. It does not fan out.
- **Two review→fix rounds on the same diff without convergence is the cap.** Stop and surface the situation to the owner with a recommendation instead of starting a third round. Repeated rounds on one diff are evidence the approach is wrong, not that the fixes are nearly done. When an implementer's measurement against real data contradicts a reviewer's model, the measurement wins (see **Honest measurement** in §7).

## 6. Rationale goes where reviewers can see it

- Do not create a decisions log.
- Put needed rationale in an issue, the effort plan, a design document, or the PR.
- One-way-door architecture decisions get an ADR (see `architect`).
- Unverified vulnerability claims are never published.

## 7. Working norms

- **Anything that can be done now gets done now** — environment setup runs immediately, outside tracked tasks, so problems surface before the first task's pipeline.
- **Honest measurement.** Never game a metric: a non-deterministic test stays xfail rather than being flaked green. When an implementer's measurement against real data contradicts a reviewer's model of the risk, the measurement wins (see `references/observations.md`).
- **Autonomy with accountability.** When granted an unattended run: self-merge after the gates pass, and leave owner-gated items open and annotated rather than blocking on them.
- **Check in on long-running subagents every 15 minutes.** A delegated task still "running" isn't proof it's progressing. Read back its actual output or status and confirm real progress, not just that the process is alive. Prefer a free, independent spot-check of the environment (`git status`, `docker ps`, GPU/resource stats, artifact directories) before spending a message or resume on asking the agent itself. Stalled or looping work gets interrupted and redirected, not left to burn budget silently.
- **The 15-minute spot-check includes CI.** Is the task parked on a CI watch past the ceiling? (`gh run list` is free)
- **CI watches are bounded, not open-ended, and post-push checks-absence needs one short poll first** (see `references/observations.md`). Brief subagents with the CI ceiling and re-run rule, never an open-ended `--watch`.
- **Subagents never passively wait on background work — they poll in a bounded foreground loop instead** (see `references/observations.md`).

## Adapting to a new environment

On first use in a tool or repo, map each element to what exists: which review skills stand in for the gates, whether a board and `docs/CURR-AGENT-EFFORT.md` carry the plan, whether subagents or phase separation carry the role split. State the mapping once, then follow it. Do not silently drop the elements the environment makes awkward. With no subagents and only a local model, see `local-llm-loop`: its driver runs the simplify, security, and code-review gates as sequential fresh-process stages.
