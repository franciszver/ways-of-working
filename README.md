# ways-of-working

A library of skills, playbooks, rules, and configs that capture one owner's ways of working, written so that **any model, including cheaper and local ones, produces near-frontier output**: Opus/Sonnet in Claude Code, free local models in Claude Code via `ANTHROPIC_BASE_URL` (Ollama, LM Studio), Antigravity, Cursor, Gemini CLI, and any MCP-capable agent.

The premise: most of the gap between a mediocre run and a frontier run is **process, not raw intelligence** — dropped requirements, unverified "done", shotgun debugging, premature stopping. Process can be written down. This repo is that writing, plus the judgment about which model should do what (`playbooks/ROUTING.md`).

## Map

```
skills/          34 canonical skills — source of truth, tuned for Opus/Sonnet
skills-local/    compact imperative variants for local models (quality, iterate,
                 debug, deep-review, prove, + 26 more) — free tokens change the discipline
agents/          Claude Code subagents: code-reviewer, verifier, researcher, architect
claude-md/       always-on CLAUDE.md layers: global-frontier, global-local, project template
playbooks/       ROUTING.md (which model for what) · HANDOFF.md (cross-tool continuity)
hooks/           Claude Code hooks: guardrails, opt-in test gate, format-on-stop
antigravity/     .agents/ port: 5 rules + 34 thin workflow stubs (loads skills/)
ports/           AGENTS.md (single portable entry point) · cursor/ (3 .mdc rules; skills/ read natively)
mcp-server/      the library as an MCP server (skills as prompts + list/get/route tools)
install.sh       one command per environment (run with --dry-run first)
```

## Install as a Claude Code plugin

The headline path for Claude Code is the plugin, not `install.sh`. It installs the 34 canonical skills, the agents, and the hooks in one step:

```bash
claude plugin marketplace add franciszver/ways-of-working
claude plugin install ways-of-working@ways-of-working
```

`install.sh` still covers every other target: local/frontier profile switching, per-project installs, and the non-Claude-Code ports (Antigravity, Cursor, Gemini CLI, AGENTS.md, MCP). See the quickstarts below.

Releases are tagged `vX.Y.Z` and listed on the [GitHub Releases](https://github.com/franciszver/ways-of-working/releases) page.

## Quickstarts

**Claude Code, frontier models (Opus/Sonnet):**
```bash
./install.sh --claude-user --profile frontier      # skills + agents + playbooks + CLAUDE.md rules
./install.sh --claude-project ~/code/myrepo        # per-repo instead / additionally
./install.sh --hooks ~/code/myrepo                 # optional automation
```

**Claude Code, local models:** the official path is `ANTHROPIC_BASE_URL` pointed at a local server that implements the Anthropic Messages API:
```bash
export ANTHROPIC_BASE_URL=http://localhost:11434   # your local server's address
./install.sh --claude-user --profile local         # on the machine/config running local models
```
Versions, ports, auth tokens, and the community `claude-code-router` alternative: [`skills-local/README.md`](skills-local/README.md). One profile per setup — the packs share skill names by design (same muscle memory, opposite token economics; see below).

**Antigravity:** `./install.sh --antigravity ~/code/myrepo` → 5 rules + 34 thin workflow stubs, one per canonical skill, plus `skills/` itself (see `antigravity/README.md`)

**Cursor:** `./install.sh --skills ~/code/myrepo/.cursor/skills` (native `SKILL.md`) + `./install.sh --cursor ~/code/myrepo` (the 3 rules `SKILL.md` can't express) · **Gemini CLI (paid tier):** `./install.sh --skills ~/.gemini/skills` (context-file options: `ports/gemini/README.md`)

**Any harness that reads AGENTS.md and/or `.agents/skills` (Codex CLI, GitHub Copilot, Cursor, OpenCode, Zed, JetBrains Junie, Amp, …):** `./install.sh --generic ~/code/myrepo` → `AGENTS.md` plus `.agents/skills` · user scope only: `./install.sh --generic-user`. (`--agents-md` is the old name for `--generic`, kept for compatibility.) Fill in AGENTS.md's "Project commands" section after install; `--force` refreshes it and backs up the previous copy to `AGENTS.md.bak`. Full harness list: "Other harnesses" below.

**Any MCP agent:** `./install.sh --mcp` prints registration; smoke-test first per `mcp-server/README.md`.

## Other harnesses

Every harness below reads Agent Skills or AGENTS.md, or both. `--generic`
covers the ones that read the shared `.agents/skills` path.

| Harness | Reads `SKILL.md` from | Reads `AGENTS.md` | Install command |
|---|---|---|---|
| Codex CLI | `.agents/skills` | yes | `--generic` |
| GitHub Copilot | `.agents/skills` or `.github/skills` | yes | `--generic` |
| Cursor | `.agents/skills` or `.cursor/skills` | yes | `--generic` |
| OpenCode | `.agents/skills` | yes | `--generic` |
| Zed | `.agents/skills` | yes | `--generic` |
| JetBrains Junie | `.agents/skills` or `.junie/skills` | yes | `--generic` |
| Amp | `.agents/skills` | yes | `--generic` |
| Antigravity | `.agents/skills` | partial | `--antigravity` |
| Gemini Code Assist | `.agents/skills` | GEMINI.md instead | `--generic` + point GEMINI.md at AGENTS.md |
| Kiro | `~/.kiro/crew/skills` | no | `--generic-user` then copy; not supported here |
| Cline | `.cline/skills` or `.claude/skills` | unconfirmed | not supported here |
| Aider | none, via `read:` in `.aider.conf.yml` | — | point it at AGENTS.md |

Roo Code, Windsurf Cascade, and free Gemini CLI were retired in 2026.

Source: survey of vendor docs, 2026-09-13; see each harness's skills
documentation — [Codex](https://learn.chatgpt.com/docs/build-skills),
[Copilot](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills),
[Cursor](https://cursor.com/help/customization/skills),
[OpenCode](https://opencode.ai/docs/skills),
[Zed](https://zed.dev/docs/ai/skills),
[Junie](https://junie.jetbrains.com/docs/agent-skills.html),
[Amp](https://ampcode.com/news/agent-skills),
[Antigravity](https://antigravity.google/docs/skills),
[Gemini](https://geminicli.com/docs/cli/skills),
[Kiro](https://kiro.dev/docs/skills),
[Cline](https://docs.cline.bot/customization/skills),
[Aider](https://aider.chat/docs/usage/conventions.html).

## The skills (canonical)

**Core process**

| | | |
|---|---|---|
| `lean-max-effort` — process backbone | `spec` — requirements ledger | `architect` — tradeoffs & ADRs |
| `breakdown` — verifiable task cards | `debug` — hypothesis-driven | `deep-review` — verified findings |
| `prove` — evidence before "done" | `refactor` — behavior-preserving | `testgen` — tests that hunt bugs |
| `research` — triangulate & cite | `write` — one structured revision | `handoff` — cold-resume briefs |
| `apply-working-process` — the owner's standard operating process | `ste-writing` — Simplified Technical English prose | `plain-language` — strike the published signs of AI writing |

**SE gaps**

| | | |
|---|---|---|
| `sec-audit` — high-confidence vuln report | `perf` — profile-first optimization | `ci-triage` — red-build triage |
| `migrate` — reversible upgrades & migrations | `api-design` — consumer-first interface design | `declutter` — cleanup-only pre-PR pass |
| `frontend-design` — designed, not defaulted, UI | | |

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
| `prompt-eng` — prompts engineered like software | `research-codebase` — documentarian codebase mapping | `demo-video` — captioned demo video + README gif |

> **Naming notes:** `sec-audit` dodges the `/security-review` builtin; `declutter` dodges `/simplify`; `deep-review`/`prove`/`iterate` dodge `/review`/`verify`/`loop`. See `skills/README.md`.

Full catalog and composition map: [`skills/README.md`](skills/README.md).

## How to Use & Maximize the Library

To get the most out of this library, follow these standard operation models for typical development workflows.

### 1. How to Invoke Skills in Your Tool
* **Claude Code**: Type `/name` (e.g., `/debug`, `/prove`) or simply refer to the skill's name and intent in your prompt.
* **Antigravity CLI**: Call the stub workflows as slash commands (e.g. `/sec-audit`, `/perf`); each loads its matching skill from `skills/`. Baseline rules are always active in `.agents/rules/baseline.md`.
* **Cursor**: Reads `SKILL.md` natively from `.cursor/skills/`; the `.mdc` rules in `.cursor/rules/` (baseline + two glob-scoped rules) load contextually alongside it.
* **Gemini CLI (paid tier)**: Reads `SKILL.md` natively from `~/.gemini/skills/`.
* **MCP Agents**: Call `list_skills` to discover skills and `get_skill` to inject a skill's full text directly into your context, or call `route` for prompt-based direction.

### 2. Recommended Skill Chains (Workflows)

* **Feature Implementation (The Full Pipeline)**:
  1. Capture requirements with `spec` to build a clean ledger and eliminate fuzzy goals.
  2. Map out tradeoffs and define one-way doors with `architect`.
  3. Decompose the plan into clear task cards with `breakdown`.
  4. Implement the feature.
  5. Run `prove` to assert evidence-based verification before declaring completion.
* **Hypothesis-Driven Debugging**:
  1. Run `debug` to diagnose failures, construct a localized hypothesis, and implement a focused fix.
  2. Gate the fix with `prove` to verify it against the original problem and watch for regressions.
  3. Sweep the clean diff with `declutter` to remove leftover prints, commented-out logic, and minor clutter.
* **Pre-flight & Shipping Review**:
  1. Run `sec-audit` on the diff to check for high-confidence security vulnerabilities.
  2. Perform a general adversarial pass with `deep-review` to locate logical bugs.
  3. Clean up formatting and dead weight with `declutter`.

### 3. The Architect-Executor Split (Multi-Model Pattern)
This is the highest-leverage pattern in the library for saving API costs:
1. **Frontier Model (e.g., Opus/Sonnet)**: Draft the `spec`, write the `architect` design, and compile the `breakdown` cards.
2. **Handoff**: Write a `HANDOFF.md` brief specifying the context, ledger, and next actions.
3. **Cheap Executor (e.g., Haiku or Local Model)**: Load `skills-local/quality` and execute individual `breakdown` task cards one at a time.
4. **Frontier Model (e.g., Sonnet)**: Spin up a fresh session to review the accumulated diffs using `deep-review` or `prove` before merging.

### 4. Continuity and ESCALATION Protocol
Keep sessions token-lean. As context windows grow, LLM instruction-following degrades:
* Avoid running massive single sessions. If a task spans multiple hours or shifts models, use the `handoff` skill to serialize the workspace state into a `HANDOFF.md` file.
* If a cheap model or executor fails to resolve a debugging problem after **3 hypothesis-driven loops** (`debug`), escalate the task up-tier. Pass the `HANDOFF.md` explaining what was tried to avoid repeating failed paths.

---

## Design principles

- **Token-cost asymmetry.** Paid models get the lean discipline (cut narration, surgical reads); free local models get the opposite ("token usage is not a concern" — mandatory self-review loops). Same goals, opposite budgets. This is why profiles exist and why installing both on one setup is wrong.
- **Verification gates everything.** Every variant of every skill ends in evidence: run the real thing, quote the decisive line, "I verified / I did not verify".
- **Judgment serialized, then executed cheaply.** Expensive models write specs, breakdowns, and handoffs; cheap models execute well-specified cards; review closes the loop (`ROUTING.md`).
- **Canonical + compressions.** `skills/` is the source of truth; `skills-local/`, `antigravity/`, `ports/` are compressions. Edits to judgment propagate outward (`ports/README.md` lists the sync points).
- **Names dodge builtins.** `deep-review`, `prove`, `iterate` avoid colliding with Claude Code's `/review`, `/verify`, `/loop`.

## Maintenance

Any capable model maintains this library *using the library itself*: follow `skills/write` + `skills/deep-review` when editing skills; keep ports in sync (`ports/README.md`); re-verify dated facts (ROUTING.md pricing, external formats) before trusting them. The MCP server, install.sh, and hooks were smoke-tested end-to-end on 2026-07-06 (details in their READMEs); what remains untested is sustained real-world use — tracked on the GitHub Issues board.

History and phase log: [`PLAN.md`](PLAN.md).

## License

MIT — see [`LICENSE`](LICENSE). The `research-codebase` skill is adapted from [Humanlayer's](https://github.com/humanlayer/humanlayer) public `research_codebase` command, with credit in the skill itself.
