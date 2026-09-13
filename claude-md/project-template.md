<!-- CLAUDE.md template for a project. Copy to <repo>/CLAUDE.md and fill in.
     Rule for what belongs here: ONLY what the model cannot derive from the code —
     verbatim commands, intent, tribal knowledge, traps. Do not paste architecture
     essays or API docs; the model can read the code. Every line is loaded every
     session, so a 40-line CLAUDE.md beats a 400-line one. Delete every section
     that doesn't earn its place, and delete these comments when done. -->

# <project name>

<!-- If this repo already has an AGENTS.md that other coding agents read, uncomment
     the next line instead of duplicating its content — Claude Code expands @-imports
     at session start. See claude-md/rules/ for path-scoped rules (debugging,
     code-changes, prose-style); install.sh --claude-project installs them into
     .claude/rules/. -->
<!-- @AGENTS.md -->

<!-- One sentence: what this is and who it's for. Sets intent, prevents wrong-audience decisions. -->

## Commands

<!-- Verbatim, copy-paste runnable. Wrong or stale commands here are worse than none. -->

- Build: `<command>`
- Test (all): `<command>` · Test (one file): `<command with placeholder>`
- Lint/format: `<command>`
- Run locally: `<command>` — then verify at `<url or check>`

## Before claiming done

<!-- The project's definition of verified. The prove skill uses this as its floor. -->

- `<the check that must pass — e.g. "npm test && npm run typecheck">`
- <manual smoke check if any — e.g. "load /dashboard, confirm chart renders">

## Architecture in five lines

<!-- Only the load-bearing shape a newcomer can't quickly grep out: where requests
     enter, where state lives, what talks to what. Five lines, not fifty. -->

## Conventions that differ from defaults

<!-- Only deviations. "We use prettier" is noise; "errors are returned, never
     thrown, except in handlers/" is signal. -->

## Danger zones

<!-- Where mistakes are expensive and why. The model treats these with prove-level
     rigor and asks before touching them. -->

- `<path or system>` — <why it's dangerous, what to check first>

## Gotchas

<!-- The traps that cost someone an afternoon: the test that needs a running
     daemon, the config that looks unused but isn't, the flaky suite. -->

## Pointers

<!-- Only files that exist and are maintained. -->

- Spec/tasks: `<SPEC.md / TASKS.md>` · Active handoff: `HANDOFF.md` (read it first if present)
