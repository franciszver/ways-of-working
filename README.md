# fable-quality-library

A library of quality-process skills, playbooks, rules, and configs — authored by Claude Fable 5 while access lasted — that makes **cheaper models produce near-frontier output**: Opus/Sonnet in Claude Code, free local models via claude-code-router, Antigravity, Cursor, Gemini CLI, and any MCP-capable agent.

The premise: most of the gap between a mediocre run and a frontier run is **process, not raw intelligence** — dropped requirements, unverified "done", shotgun debugging, premature stopping. Process can be written down. This repo is that writing, plus the judgment about which model should do what (`playbooks/ROUTING.md`).

## Map

```
skills/          29 canonical skills — source of truth, tuned for Opus/Sonnet
skills-local/    compact imperative variants for local models (quality, iterate,
                 debug, deep-review, prove, + 17 new skills) — free tokens change the discipline
agents/          Claude Code subagents: code-reviewer, verifier, researcher, architect
claude-md/       always-on CLAUDE.md layers: global-frontier, global-local, project template
playbooks/       ROUTING.md (which model for what) · HANDOFF.md (cross-tool continuity)
hooks/           Claude Code hooks: guardrails, opt-in test gate, format-on-stop
antigravity/     .agent/ port: 5 rules + 24 workflows
ports/           AGENTS.md (generic single-file port) · cursor/ (22 .mdc rules) · gemini/ (22 commands)
mcp-server/      the library as an MCP server (skills as prompts + list/get/route tools)
install.sh       one command per environment (run with --dry-run first)
```

## Quickstarts

**Claude Code, frontier models (Opus/Sonnet):**
```bash
./install.sh --claude-user --profile frontier      # skills + agents + CLAUDE.md rules
./install.sh --claude-project ~/code/myrepo        # per-repo instead / additionally
./install.sh --hooks ~/code/myrepo                 # optional automation
```

**Claude Code, local models (claude-code-router):**
```bash
./install.sh --claude-user --profile local         # on the machine/config running local models
```
One profile per setup — the packs share skill names by design (same muscle memory, opposite token economics; see below).

**Antigravity:** `./install.sh --antigravity ~/code/myrepo` → rules + 24 workflows (`/spec /architect /breakdown /debug /deep-review /prove /handoff /sec-audit /perf /ci-triage /migrate /api-design /declutter /incident /postmortem /release /onboard /estimate /pr-workflow /data-analysis /brainstorm /explain /prompt-eng /research-codebase`)

**Any AGENTS.md tool (Codex, Amp, Zed, Jules, …):** `./install.sh --agents-md ~/code/myrepo`

**Cursor:** `./install.sh --cursor ~/code/myrepo` · **Gemini CLI:** `./install.sh --gemini global` (context-file options: `ports/gemini/README.md`)

**Any MCP agent:** `./install.sh --mcp` prints registration; smoke-test first per `mcp-server/README.md`.

## The skills (canonical)

**Core process**

| | | |
|---|---|---|
| `lean-max-effort` — process backbone | `spec` — requirements ledger | `architect` — tradeoffs & ADRs |
| `breakdown` — verifiable task cards | `debug` — hypothesis-driven | `deep-review` — verified findings |
| `prove` — evidence before "done" | `refactor` — behavior-preserving | `testgen` — tests that hunt bugs |
| `research` — triangulate & cite | `write` — one structured revision | `handoff` — cold-resume briefs |

**SE gaps**

| | | |
|---|---|---|
| `sec-audit` — high-confidence vuln report | `perf` — profile-first optimization | `ci-triage` — red-build triage |
| `migrate` — reversible upgrades & migrations | `api-design` — consumer-first interface design | `declutter` — cleanup-only pre-PR pass |

**Ops & incidents**

| | | |
|---|---|---|
| `incident` — production incident response | `postmortem` — blameless retrospective | `release` — staged exposure deploys |

**Codebase navigation**

| | | |
|---|---|---|
| `onboard` — fast accurate codebase orientation | `estimate` — calibrated range estimates | `pr-workflow` — branch-to-merge hygiene |

**Non-engineering**

| | | |
|---|---|---|
| `data-analysis` — scrutiny-proof analysis | `brainstorm` — structured ideation | `explain` — learner-targeted explanations |
| `prompt-eng` — prompts engineered like software | `research-codebase` — documentarian codebase mapping | |

> **Naming notes:** `sec-audit` dodges the `/security-review` builtin; `declutter` dodges `/simplify`; `deep-review`/`prove`/`iterate` dodge `/review`/`verify`/`loop`. See `skills/README.md`.

Full catalog and composition map: [`skills/README.md`](skills/README.md).

## Design principles

- **Token-cost asymmetry.** Paid models get the lean discipline (cut narration, surgical reads); free local models get the opposite ("token usage is not a concern" — mandatory self-review loops). Same goals, opposite budgets. This is why profiles exist and why installing both on one setup is wrong.
- **Verification gates everything.** Every variant of every skill ends in evidence: run the real thing, quote the decisive line, "I verified / I did not verify".
- **Judgment serialized, then executed cheaply.** Expensive models write specs, breakdowns, and handoffs; cheap models execute well-specified cards; review closes the loop (`ROUTING.md`).
- **Canonical + compressions.** `skills/` is the source of truth; `skills-local/`, `antigravity/`, `ports/` are compressions. Edits to judgment propagate outward (`ports/README.md` lists the sync points).
- **Names dodge builtins.** `deep-review`, `prove`, `iterate` avoid colliding with Claude Code's `/review`, `/verify`, `/loop`.

## Maintenance after Fable

Any capable model maintains this library *using the library itself*: follow `skills/write` + `skills/deep-review` when editing skills; keep ports in sync (`ports/README.md`); re-verify dated facts (ROUTING.md pricing, external formats) before trusting them. The MCP server, install.sh, and hooks were smoke-tested end-to-end on 2026-07-06 (details in their READMEs); what remains untested is sustained real-world use — PLAN.md's Day-2 tuning.

History and phase log: [`PLAN.md`](PLAN.md).
