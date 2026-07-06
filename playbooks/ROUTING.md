# ROUTING.md — which model for what work

The judgment layer for a mixed fleet: frontier Claude models in Claude Code, free local models via claude-code-router, and Antigravity. Goal: **maximize quality-per-dollar by routing each task to the cheapest tier that can deliver it — with verification as the safety net.**

Pricing and model facts below are **as of 2026-07** (source: Anthropic docs). Prices and lineups rot; principles don't. Re-check numbers before relying on them (`/claude-api` in Claude Code, or platform.claude.com/docs/en/pricing).

## The fleet

| Tier | Models (2026-07) | $/MTok in/out | Marginal cost feel |
|---|---|---|---|
| Frontier-max | Fable 5 (`claude-fable-5`) | $10 / $50 | ~2× Opus, 10× Haiku |
| Opus | Opus 4.8 (`claude-opus-4-8`) | $5 / $25 | ~1.7× Sonnet |
| Sonnet | Sonnet 5 (`claude-sonnet-5`) | $3 / $15 (intro $2/$10 through 2026-08) | the workhorse baseline |
| Haiku | Haiku 4.5 (`claude-haiku-4-5`) | $1 / $5 | ~1/3 Sonnet; 200K ctx cap |
| Local | Qwen, GPT-OSS via claude-code-router | $0 | free tokens, weaker judgment, slower |
| Antigravity | Gemini 3 family | plan-dependent | treat by capability tier, not brand |

Output tokens dominate agentic cost (5× input price), so verbose tiers cost more than their input price suggests.

## Five principles

**1. Route by cost-of-being-wrong, not difficulty.** A task with a cheap objective check (tests, compiler, schema) can go to a cheap model — verification catches failures at near-zero cost. A task whose failure is expensive to detect or undo (architecture, public API, data migration, anything one-way-door) goes up-tier, because you're paying for judgment you can't cheaply audit. "Hard but checkable" routes down; "easy but unauditable" routes up.

**2. The token-cost asymmetry flips the process advice.** Paid models get the lean discipline (`skills/lean-max-effort`): cut narration, read surgically, one structured revision pass. Local models get the opposite (`skills-local/quality`): token usage is not a concern — burn freely on self-review loops, mandatory verification rounds, re-reading from disk. Never install the lean discipline on a free model or unbounded loops on a paid one; each is the other's failure mode.

**3. Downshift through a handoff, never a raw context switch.** The expensive model's output that makes cheap execution safe is a *specification*: `spec` ledger + `breakdown` task cards + `handoff` brief. A cheap model executing a well-specified task card performs near its ceiling; the same model interpreting a vague request performs at its floor. Spend frontier tokens on making tasks unambiguous, then execution is nearly free.

**4. Escalate on defined triggers, not frustration.** Escalation is cheapest early. Hand up-tier (with a `handoff` brief stating what was tried) when:
- the same failure survives 3 hypothesis-driven attempts (`debug`'s widening rule), or 2 attempts of the same fix;
- requirements turn out contradictory or the spec is wrong (don't let an executor re-architect);
- a one-way-door decision surfaces mid-task (schema, public interface, destructive migration);
- the task needs judgment the tier can't verify itself producing (novel design, subtle concurrency, security).
A truthful "stuck, here's the state" from a cheap model costs cents; a confident wrong answer costs the redo *plus* the debugging of trust.

**5. Effort is a routing dimension inside a model.** On Claude 4.6+, `effort` (low/medium/high/xhigh/max) reshapes cost more than switching between adjacent tiers: low effort produces fewer, more consolidated tool calls and terser output. Sonnet at high effort often beats Opus at low. Defaults: `high` for most work, `xhigh` for hard coding/agentic runs, `low`/`medium` for mechanical tasks and subagents. In Claude Code: `/effort`.

## Task → tier

| Task | Tier | Why |
|---|---|---|
| Architecture, API design, data model (`architect`) | Highest available | One-way doors; wrong is expensive and slow to surface |
| Spec-writing, task breakdown (`spec`, `breakdown`) | High | This output multiplies every downstream tier's quality |
| Gnarly debugging: concurrency, heisenbugs, cross-system | High | Hypothesis quality is the bottleneck |
| Security-sensitive review (`deep-review`) | High + fresh context | Missed findings are the expensive kind of cheap |
| Routine feature with clear spec | Sonnet or local+`quality` | Cheap to verify against the spec's criteria |
| Ordinary bugfix with repro | Sonnet; local if tests exist | The repro is the verifier |
| Tests from a spec (`testgen`) | Sonnet / local | Contract is written; boundary tables are mechanical-ish |
| Mechanical refactors, renames, migrations by pattern | Haiku / local | Tools + tests verify; judgment need is low |
| Boilerplate, scaffolding, config plumbing | Haiku / local | |
| Research synthesis & writing (`research`, `write`) | Opus/Sonnet | Judgment-dense; hallucination risk scales down-tier |
| Bulk collection, scraping, format conversion | Haiku / local | Volume work, checkable output |
| Summaries, commit messages, doc touch-ups | Haiku | |
| Review of local-model output | Sonnet+ | The supervisor pattern (below) |

## Patterns

- **Architect–executor split.** Frontier model produces spec + breakdown + handoff; cheap models execute task cards; frontier reviews the assembled result once (`deep-review`). This is the highest-leverage pattern in the playbook — it converts frontier judgment into artifacts cheap models can follow.
- **Supervisor.** Local model works free under `skills-local/quality`; a paid model periodically runs `deep-review` on the accumulated diff. Cadence by stakes: every task card for production code, every session for tooling.
- **Fresh-context verifier.** Before shipping up-tier work, a *separate* cheap-model session (or `verifier` subagent) runs `prove` against the ledger. Fresh eyes at Haiku prices catch what the author's context can't see.
- **Subagent economics.** In Claude Code, subagents can run cheaper models (`model:` in the agent definition). Delegate mechanical legwork down; keep synthesis in the main thread. Note: a subagent starts cold — the task description must carry the context (mini-handoff).
- **Batch the batchable.** Non-interactive bulk work (classification, extraction over many files) through the Batches API is 50% off; overnight is fine for non-blocking work.

## Cost hygiene (paid tiers)

- Prompt caching pays for itself on the 2nd request (reads ≈0.1×) — keep prompts prefix-stable; don't edit the system prompt mid-session.
- Long sessions degrade quality *and* multiply cached-context spend: prefer ending a task with `handoff` + fresh session over pushing a tired context.
- Don't route up-tier to compensate for a vague request. Sharpening the request (`spec`, 2 minutes) is cheaper than Fable-ing a guess.

## Defaults when unsure

Sonnet, high effort, with `prove` gating "done". Escalate on the triggers above; downshift when you notice the work is mechanical. When the choice truly doesn't matter, the cheaper tier was the right answer.
