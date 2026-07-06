# ports/ — the library for every other agent tool

Compressed ports of the canonical skills for tools that read their own config formats. One rule of thumb governs them all: the always-on file carries the quality floor; per-situation depth loads contextually where the tool supports it.

| Port | Consumed by | Install |
|---|---|---|
| [`agents-md/AGENTS.md`](agents-md/AGENTS.md) | The de facto standard: Codex CLI, Cursor, Amp, Zed, Jules, Gemini CLI (configurable), many others | Copy to repo root as `AGENTS.md` |
| [`cursor/`](cursor/) | Cursor | Copy `*.mdc` into `<repo>/.cursor/rules/` |
| [`gemini/`](gemini/) | Gemini CLI | Copy `commands/` into `~/.gemini/` or `<repo>/.gemini/`; context file options in its README |
| [`../antigravity/`](../antigravity/) | Google Antigravity | Its own README |

Claude Code doesn't use these — it gets the full-fidelity versions ([`../skills/`](../skills/), [`../claude-md/`](../claude-md/), [`../agents/`](../agents/)).

## Maintenance note

These are compressions of the canonical skills, not independent documents. When a canonical skill's judgment changes (a new rule, a changed threshold), propagate to every compression: the matching `../skills-local/` variant, the `AGENTS.md` section, the matching `cursor/*.mdc`, the matching `gemini/commands/*.toml`, and the Antigravity rule/workflow. The improvement-loop checklist treats cross-surface drift as a defect.

Formats verified 2026-07: AGENTS.md is plain markdown by design; Cursor rules are `.mdc` with `description`/`globs`/`alwaysApply` frontmatter; Gemini CLI commands are TOML with `description` + `prompt` (`{{args}}` substitution) per [geminicli.com/docs/cli/custom-commands](https://geminicli.com/docs/cli/custom-commands/).
