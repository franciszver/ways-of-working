# Plan: Fable-Quality Library

**Goal:** Before Fable access ends (~2026-07-07), turn this repo into a full library of Fable-authored skills, commands, rules, playbooks, and configs so that Opus/Sonnet, local models, and Antigravity produce near-Fable quality afterward — cheaper, better, faster.

**Guiding principle:** Fable's authoring judgment is the expiring resource. Author judgment-dense content (skills, playbooks, rules) first; mechanical plumbing (MCP server, installer, ports) last — any model can finish those later *using the library itself*.

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

- [ ] **Phase 1 — Canonical skills** *(needs Fable most)*: restructure repo; author the ~12 canonical skills, SE trio (`debug`, `review`, `verify`) first.
- [ ] **Phase 2 — Judgment artifacts**: `ROUTING.md` playbook, `HANDOFF.md`, CLAUDE.md templates, subagent definitions, local skill variants.
- [ ] **Phase 3 — Ports & automation**: Antigravity `.agent/` rules + workflows (verify current format via web search first), hooks.
- [ ] **Phase 4 — Plumbing** *(any model can finish)*: MCP server (skills as MCP prompts + `list`/`get`/`route` tools), `install.sh`, per-environment quickstarts in README.
- [ ] **Day-2 reserve — Tuning on contact**: run real tasks in each environment (real bug on a local model, real task in Antigravity); tune skills based on observed friction.

## Working method

Author in batches; commit and push at every checkpoint. User interrupts anytime with corrections. After Fable access ends, Sonnet/Opus maintain the library following its own conventions.

**Optional housekeeping:** repo has outgrown "ideas" — renaming (e.g. `fable-quality-library`) is safe; GitHub redirects the old URL.

## Status log

- 2026-07-05 — Plan written. Repo contains seed skills: `claude-local-quality` (quality + loop) and `lean-max-effort`.
