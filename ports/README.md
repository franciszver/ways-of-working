# ports/ — the library for every other agent tool

`AGENTS.md` is the single portable entry point: a compact always-on floor plus one pointer line per canonical skill. Tools that read `SKILL.md` natively (Cursor, Antigravity, the paid-tier Gemini CLI) install `skills/` directly and need only a small extra port for what `SKILL.md` cannot express.

| Port | Consumed by | Install |
|---|---|---|
| [`agents-md/AGENTS.md`](agents-md/AGENTS.md) | The de facto standard: Codex CLI, Cursor, Amp, Zed, Jules, Gemini CLI (configurable), many others | Copy to repo root as `AGENTS.md` |
| [`cursor/`](cursor/) | Cursor | Cursor reads `SKILL.md` natively: `install.sh --skills <repo>/.cursor/skills`. `cursor/` adds only what `SKILL.md` cannot express: `install.sh --cursor <repo>` copies `*.mdc` into `<repo>/.cursor/rules/` |
| [`gemini/`](gemini/) | Gemini CLI (paid tier) | `install.sh --skills ~/.gemini/skills`; context file options in its README |
| [`../antigravity/`](../antigravity/) | Google Antigravity | Its own README |

Claude Code doesn't use these — it gets the full-fidelity versions ([`../skills/`](../skills/), [`../claude-md/`](../claude-md/), [`../agents/`](../agents/)).

For every other harness that reads AGENTS.md and `.agents/skills` (Codex CLI, GitHub Copilot, OpenCode, Zed, JetBrains Junie, Amp, and more), use `install.sh --generic DIR` or `--generic-user`. See the "Other harnesses" table in the root [`README.md`](../README.md).

## Maintenance note

These are compressions of the canonical skills, not independent documents. When a canonical skill's judgment changes (a new rule, a changed threshold), propagate to every compression: the matching `../skills-local/` variant, the matching `cursor/*.mdc`, and — for always-on floors — the `../claude-md/` layers and `cursor/baseline.mdc`. The improvement-loop checklist treats cross-surface drift as a defect.

The `AGENTS.md` skill pointer lines and the Antigravity workflow stubs are generated from `skills/*/SKILL.md` frontmatter — run `python3 scripts/gen-ports.py` after any description change; CI fails on drift.

Formats — last verified: see CHANGELOG — AGENTS.md is plain markdown by design; Cursor rules are `.mdc` with `description`/`globs`/`alwaysApply` frontmatter.
