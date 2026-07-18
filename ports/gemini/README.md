# ports/gemini — Gemini CLI port

Two pieces: an always-on context file and slash commands.

## Context file (the always-on layer)

Gemini CLI loads `GEMINI.md` from the project root and `~/.gemini/GEMINI.md` globally. Rather than maintain a near-duplicate, use the canonical single-file distillation:

```bash
# option A — copy it in as GEMINI.md:
cp ../agents-md/AGENTS.md <repo>/GEMINI.md

# option B — point Gemini CLI at AGENTS.md directly (settings.json):
#   { "context": { "fileName": "AGENTS.md" } }
# then keep a single AGENTS.md at the repo root for every tool at once.
```

Option B is better when the repo already ships `AGENTS.md` — one file, every tool.

## Commands (the on-demand layer)

```bash
# global (all projects):
mkdir -p ~/.gemini/commands && cp commands/*.toml ~/.gemini/commands/

# or per project, versioned:
mkdir -p <repo>/.gemini/commands && cp commands/*.toml <repo>/.gemini/commands/
```

**Core process**

| Command | Does |
|---|---|
| `/spec <request>` | Requirements ledger + acceptance criteria + non-goals |
| `/debug <failure>` | Hypothesis-driven debugging protocol |
| `/deep-review [target]` | Verified, severity-ranked review |
| `/prove [claim]` | Evidence-based verification before "done" |
| `/handoff` | Write/update the cross-tool HANDOFF.md brief |
| `/apply-working-process` | Adopt the owner's standard operating process for the session |

**SE gaps**

| Command | Does |
|---|---|
| `/sec-audit [target]` | High-confidence vuln report with concrete exploit scenarios |
| `/perf [target]` | Profile-first optimization to a numeric target |
| `/ci-triage` | Red-build triage — classify, reproduce, fix or quarantine |
| `/migrate [plan]` | Reversible upgrade/migration in expand→migrate→contract steps |
| `/api-design [spec]` | Consumer-first interface design, full contract before v1 |
| `/frontend-design [target]` | Designed, not defaulted — tokens, hierarchy, real states, verify by looking |
| `/declutter [target]` | Cleanup-only pre-PR pass — no bug fixes, no redesign |

**Ops & incidents**

| Command | Does |
|---|---|
| `/incident` | Production incident response — mitigate before diagnosing |
| `/postmortem` | Blameless retrospective — plural causes, owned action items |
| `/release [plan]` | Staged exposure deploys — verify, ramp, watch, rollback-ready |

**Codebase navigation**

| Command | Does |
|---|---|
| `/onboard [area]` | Fast accurate codebase orientation — trace one real flow |
| `/estimate <task>` | Calibrated range estimate with stated uncertainty |
| `/pr-workflow` | Branch-to-merge hygiene — commits, description, review response |

**Non-engineering**

| Command | Does |
|---|---|
| `/data-analysis [question]` | Analysis that survives scrutiny — interrogate before computing |
| `/brainstorm <topic>` | Structured ideation — generate wide, converge with criteria |
| `/explain <concept>` | Learner-targeted explanation — anchor, concrete before abstract |
| `/prompt-eng [prompt]` | Prompts engineered like software — spec, examples, eval set |
| `/research-codebase <topic>` | Documentarian codebase mapping with file:line evidence |

Format (TOML, `description` + `prompt`, `{{args}}` substitution) verified 2026-07 against [geminicli.com/docs/cli/custom-commands](https://geminicli.com/docs/cli/custom-commands/).
