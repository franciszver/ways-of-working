# Plan: Ways-of-Working Library

> Historical plan. Frozen; live plan is GitHub Issues.

**Goal:** While frontier-model access lasted, turn this repo into a full library of frontier-authored skills, commands, rules, playbooks, and configs so that Opus/Sonnet, local models, and Antigravity produce near-frontier quality afterward — cheaper, better, faster.

**Guiding principle:** Frontier authoring judgment is the expiring resource. Author judgment-dense content (skills, playbooks, rules) first; mechanical plumbing (MCP server, installer, ports) last — any model can finish those later *using the library itself*.

## Targets

| Environment | How it consumes the library |
|---|---|
| Claude Code — Opus/Sonnet | Canonical `SKILL.md` skills, subagents, hooks, CLAUDE.md templates |
| Claude Code — local models (Qwen, GPT-OSS via claude-code-router) | Compact, forceful skill variants + local CLAUDE.md snippet |
| Antigravity CLI | Full port: `.agent/rules/` (always-on baseline) + `.agent/workflows/` (command ports) |
| Any MCP-capable agent | Local MCP server exposing skills as prompts + fetch/route tools |

**Priority workflows:** software engineering · research & writing · planning & architecture.

## Repo structure

```
skills/           canonical skills — source of truth (Opus/Sonnet grade)
skills-local/     compact variants tuned for local models (top skills only)
agents/           Claude Code subagent definitions (reviewer, verifier, researcher, architect)
hooks/            settings.json snippets + scripts (format-on-stop, test gate, guardrails)
claude-md/        CLAUDE.md templates: global-frontier, global-local, per-project
antigravity/      .agent/rules + .agent/workflows ports
playbooks/        ROUTING.md (which model for what task) + HANDOFF.md (session continuity)
mcp-server/       local stdio MCP server (Python, official mcp SDK)
install.sh        one command to install into ~/.claude, a project's .agent/, or register the MCP
README.md         library index + per-environment quickstart
```

## Skill catalog

**Core**
- `lean-max-effort` — process backbone: Capture → Plan → Execute lean → Verify *(exists)*
- `handoff` — compact context handoff so a cheap model resumes exactly where a smart one left off

**Software engineering**
- `debug` — hypothesis-driven debugging, no shotgun
- `review` — severity-ranked, verified findings
- `verify` — prove-it-works before "done"
- `refactor` — behavior-preserving refactor protocol
- `testgen` — tests that hunt edge cases, not coverage theater

**Research & writing**
- `research` — triangulate sources, log citations, synthesize
- `write` — audience → outline → draft → one structured revision pass

**Planning & architecture**
- `spec` — requirements ledger + acceptance criteria
- `architect` — design doc, tradeoffs, ADR format
- `breakdown` — decompose into verifiable tasks agents can execute

**Local variants** (`skills-local/`): existing `quality` + `loop`, plus compacted `debug` / `review` / `verify` — local models mostly do coding, so that's where tuned copies pay off.

## Phases

- [x] **Phase 1 — Canonical skills** *(needs the strongest model most)*: restructure repo; author the ~12 canonical skills, SE trio first. *(Names shifted to dodge Claude Code builtins: `deep-review`, `prove`; local `loop`→`iterate`.)*
- [x] **Phase 2 — Judgment artifacts**: `ROUTING.md` playbook, `HANDOFF.md`, CLAUDE.md templates, subagent definitions, local skill variants.
- [x] **Phase 3 — Ports & automation**: Antigravity `.agent/` rules + workflows (format verified via web search 2026-07), hooks; scope grew per user decision to include AGENTS.md, Cursor, and Gemini CLI ports (`ports/`).
- [x] **Phase 4 — Plumbing** *(authored, not executed — smoke tests in the READMEs)*: MCP server (skills as MCP prompts + `list`/`get`/`route` tools), `install.sh`, per-environment quickstarts in README.
- [ ] **Day-2 reserve — Tuning on contact**: run real tasks in each environment (real bug on a local model, real task in Antigravity); tune skills based on observed friction. *(Smoke tests done 2026-07-06 — see status log.)*

## Working method

Author in batches; commit and push at every checkpoint. User interrupts anytime with corrections. Afterwards, Sonnet/Opus maintain the library following its own conventions.

**Optional housekeeping:** ~~repo has outgrown "ideas" — renaming (e.g. `ways-of-working`) is safe; GitHub redirects the old URL.~~ *Done 2026-07-06: renamed the repo (earlier names dropped); 2026-09-13: renamed to ways-of-working.*

## Status log

- 2026-07-05 — Plan written. Repo contains seed skills: `claude-local-quality` (quality + loop) and `lean-max-effort`.
- 2026-07-05 — Restructured into library layout; Phase 1 complete (12 canonical skills); Phase 2 complete (playbooks, CLAUDE.md templates, 4 subagents, local trio).
- 2026-07-06 — Phase 3 complete (Antigravity rules+workflows, AGENTS.md/Cursor/Gemini ports, hooks). Phase 4 complete (MCP server, install.sh, README) — plumbing authored, not executed. Improvement loop running until 3 consecutive clean passes.
- 2026-07-06 — Improvement loop complete: 14 passes, 16 fixes (passes 1–7, 9, 11), then 3 consecutive clean passes (12–14). Every file re-read in full since authoring; mechanical suite (frontmatter, links, fences, TOML/JSON shape, bash/python syntax parse) green; guardrails + route() regexes statically behavior-checked. Remaining: Day-2 reserve only.
- 2026-07-06 — Smoke tests executed, all green, zero fixes needed: install.sh (every target against a scratch HOME, dry-run, idempotent reruns, error cases), guardrails/test-gate/format-on-stop hooks end-to-end, MCP server 11/11 over real stdio (uv + Python 3.12 + mcp SDK). Note: authoring machine has only Python 3.9 and no uv — real MCP registration needs uv (or Python ≥3.10) installed first. Remaining: tuning on contact.
- 2026-07-07 — Library expansion: 17 new canonical skills authored across four areas (SE gaps: sec-audit, perf, ci-triage, migrate, api-design, declutter; ops: incident, postmortem, release; codebase nav: onboard, estimate, pr-workflow; non-engineering: data-analysis, brainstorm, explain, prompt-eng, research-codebase). `/code-review` behaviors folded into deep-review (no new skill). All 17 propagated to all 5 compression surfaces: skills-local/ variants, Antigravity workflows, Gemini CLI TOMLs, Cursor .mdc rules, AGENTS.md sections. MCP server route() hints and instructions string updated. All READMEs updated. Improvement loop completed to 3 consecutive clean passes.
- 2026-07-18 — Added `apply-working-process` skill (the owner's standard operating process, distilled from the AgentForge Phase 1 execution model: orchestrator-only role split with cheap-model implementation + fresh equal-or-better review, board-as-plan issue discipline, one issue = one branch = one PR, red-first strict TDD, three gates before merge, same-session decision logging in local `prd/DECISIONS.md`, three-tier visibility) across all 6 surfaces: canonical `skills/`, `skills-local/`, Antigravity workflow, Gemini CLI TOML, Cursor `.mdc`, AGENTS.md section. MCP server route() hints and instructions string updated; all READMEs updated.
- 2026-07-08 — Added `frontend-design` skill (UI/visual design quality: design-language tokens before components, hierarchy before decoration, real states, verify-by-looking) across all 6 surfaces: canonical `skills/`, `skills-local/`, Antigravity workflow, Gemini CLI TOML, Cursor `.mdc`, AGENTS.md section. MCP server route() hints and instructions string updated; all READMEs updated. Improvement loop run to a clean pass on new/touched files.
- 2026-07-20 — Updated `apply-working-process`: orchestrator now defaults to the strongest available tier and offers to fall back to Opus at high reasoning effort if the seat lacks that tier (rather than silently downgrading); added a norm to check in on long-running subagents every 20 minutes to confirm real progress, not just liveness. Propagated to all 5 ported surfaces (`skills-local/`, Antigravity, Cursor `.mdc`, Gemini CLI TOML — AGENTS.md has no per-skill section for this one).
- 2026-07-21 — Updated `apply-working-process` norms: (1) tightened the subagent check-in cadence from every 20 minutes to every 15, and added the refinement to prefer a free, independent spot-check of the environment (git status, docker ps, GPU/resource stats, artifact directories) over spending a message/resume on asking the agent; (2) added a new standing norm — no passive waiting — every subagent brief must instruct the agent to never end its turn to "wait" on a background/detached/slow process (detached work produces no wake-up notification, so it would sleep forever), and instead poll inline in a bounded foreground loop and continue in the same turn; long-running work is launched foreground or harness-tracked, never detached-and-then-stopped. Prompted by an observed failure mode on 2026-07-21: a subagent stopped to await a notification that could never arrive, twice in one task. Propagated to all 5 ported surfaces (`skills-local/`, Antigravity, Cursor `.mdc`, Gemini CLI TOML — AGENTS.md still has no per-skill section for this one, verified via grep) plus the installed copy at `~/.claude/skills/apply-working-process/SKILL.md`.
- 2026-08-12 — Updated `apply-working-process` from a real session that cost $113 for three merged PRs (94% subagent spend; Sonnet-tier reviewers alone $69): (1) reviewer routing now tiers by what the check verifies rather than by "it's a review" — Haiku-tier for mechanical/structural checks, Sonnet-tier for ordinary correctness on contained diffs, top tier reserved for adversarial passes on high-stakes paths (data destruction/corruption, security boundaries, correctness resting on an external-system assumption), where it earned its cost twice in the source session; "fresh = no implementation context" is preserved at every tier. (2) The simplify gate now scales to the diff (small diffs get one combined cheap-tier pass covering all four angles, deviation stated explicitly; security review and code review always run at full strength), plus a two-round review→fix cap before surfacing to the owner, and a measurement-beats-reviewer-model clause in Working norms. Canonical `skills/` and `playbooks/ROUTING.md`'s task→tier table landed in commit `e061336`; the follow-up commit propagates to the 5 ported surfaces (`skills-local/`, Antigravity, Cursor `.mdc`, Gemini CLI TOML, and — for the first time — `ports/agents-md/AGENTS.md`) and re-syncs the installed copy at `~/.claude/skills/apply-working-process/SKILL.md` (verified identical by `diff`, not assumed). In `skills-local/` the simplify reduction is deliberately inverted: local tokens are free, so that pack keeps the full four-angle fan-out on every diff (per `playbooks/ROUTING.md` principle 2 — never install the lean discipline on a free model). **Correction to the 2026-07-20 and 2026-07-21 entries above:** both claim "AGENTS.md has no per-skill section for this one" (the second "verified via grep"). That premise is false — `ports/agents-md/AGENTS.md` carries a `## Standard working process` section, added 2026-07-18; the grep missed it because the section is titled by topic, not by skill name. Those two updates were therefore never propagated there. AGENTS.md is synced for *this* change only — the 2026-07-20 and 2026-07-21 norms (strongest-available-tier orchestrator default, 15-minute subagent check-ins, bounded CI watches, no passive waiting) remain unported to it and are open follow-up. Future `apply-working-process` changes must include it as a 6th surface.
