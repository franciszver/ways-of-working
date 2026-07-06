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

| Command | Does |
|---|---|
| `/spec <request>` | Requirements ledger + acceptance criteria + non-goals |
| `/debug <failure>` | Hypothesis-driven debugging protocol |
| `/deep-review [target]` | Verified, severity-ranked review |
| `/prove [claim]` | Evidence-based verification before "done" |
| `/handoff` | Write/update the cross-tool HANDOFF.md brief |

Format (TOML, `description` + `prompt`, `{{args}}` substitution) verified 2026-07 against [geminicli.com/docs/cli/custom-commands](https://geminicli.com/docs/cli/custom-commands/).
