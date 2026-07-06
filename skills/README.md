# skills/ — canonical skills (source of truth)

Judgment-dense skills tuned for frontier models (Opus, Sonnet) in Claude Code. Each is a directory with a `SKILL.md`; each doubles as a slash command (`/debug`, `/prove`, …). Compact local-model variants of the coding skills live in [`../skills-local/`](../skills-local/) — install one profile per setup, not both.

## Catalog

| Skill | One line | Reach for it when |
|---|---|---|
| [`lean-max-effort`](lean-max-effort/) | Process backbone: Capture → Plan → Execute lean → Verify | Start of any non-trivial task |
| [`spec`](spec/) | Requirements ledger + acceptance criteria + non-goals | Requirements are fuzzy, or before sizable work |
| [`architect`](architect/) | Options, tradeoffs, one-way doors, ADRs | Designing, or any hard-to-reverse decision |
| [`breakdown`](breakdown/) | Decompose into verifiable tasks with DoDs and contracts | Multi-session/multi-agent work |
| [`debug`](debug/) | Hypothesis-driven debugging, no shotgun | Anything fails |
| [`deep-review`](deep-review/) | Verified, severity-ranked findings only | Reviewing a diff/PR, or attacking your own work |
| [`prove`](prove/) | Evidence before "done"; I-verified / I-did-not-verify | Before reporting completion, committing, handing off |
| [`refactor`](refactor/) | Behavior-preserving steps under a test net | Restructuring working code |
| [`testgen`](testgen/) | Tests that hunt bugs, proven able to fail | Writing/improving tests, regression tests |
| [`research`](research/) | Triangulated sources, citation log, disconfirmation | Evaluations, landscape questions, costly facts |
| [`write`](write/) | Audience → thesis → outline → draft → one revision pass | Prose is the product |
| [`handoff`](handoff/) | Continuation brief a cold session can resume from | Context pressure, session end, model downshift |

## How they compose

`lean-max-effort` is the backbone; the others deepen one of its phases: **Capture** → `spec` · **Plan** → `architect`, `breakdown` · **Execute** → `debug`, `refactor`, `testgen` · **Verify** → `prove`, `deep-review` · **Continuity** → `handoff`, with `research` and `write` covering the non-coding workflows. Skills reference each other by name where the seams are (`debug` ends in `prove`; `breakdown` cards carry `spec`-style criteria).

## Install

```bash
# global (all projects):
cp -r <these directories> ~/.claude/skills/

# or project-scoped, versioned with the repo:
cp -r <these directories> <repo>/.claude/skills/
```

Or use [`../install.sh`](../install.sh). If `~/.claude/skills/` didn't exist before the current session, restart Claude Code once. Pair with a CLAUDE.md from [`../claude-md/`](../claude-md/) — skills fire per-task; CLAUDE.md rules are always on.

## Naming notes

`deep-review`, `prove`, and `iterate` (local pack) dodge Claude Code's built-in `/review`, `/verify`, and `/loop` commands. If your Claude Code version has no conflict and you prefer the short names, rename the directory and the frontmatter `name:` together.
