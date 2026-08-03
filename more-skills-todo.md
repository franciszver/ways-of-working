# more-skills-todo.md — expansion session plan & status

> **Historical log — closed.** All batches below are complete; this is not an open todo list.

Session date: 2026-07-07. Continuation doc for the library expansion — written so any session (any model) can resume exactly here. Follow the library's own conventions: canonical `skills/` is source of truth; everything else is a compression that must stay in sync (`ports/README.md`).

## The request

Add more skills to the library. User's clarifying answers locked this scope:

- **Areas**: all four offered — SE gaps, ops & incidents, codebase navigation, non-engineering — **plus** a port of Humanlayer's public `research_codebase` command, **plus** versions of Claude Code's builtin `/simplify`, `/security-review`, `/code-review`.
- **`/code-review` handling**: fold its behaviors into the existing `deep-review` (no new skill).
- **Security skill name**: `sec-audit` (dodges the `/security-review` builtin, per library convention).
- **`/simplify` port named `declutter`** (dodges the `/simplify` builtin — same convention; decided by me, flag to user).
- **Treatment**: full — every new skill gets a `skills-local/` variant, an Antigravity workflow, a Gemini TOML command, Cursor coverage, and AGENTS.md coverage.
- **Rigor**: improvement loop until 3 consecutive clean passes, scoped to new/touched files only.

## The 17 new canonical skills

| Area | Skills |
|---|---|
| SE gaps | `sec-audit` · `perf` · `ci-triage` · `migrate` · `api-design` · `declutter` |
| Ops & incidents | `incident` · `postmortem` · `release` |
| Navigation | `onboard` · `estimate` · `pr-workflow` |
| Non-engineering | `data-analysis` · `brainstorm` · `explain` · `prompt-eng` |
| External port | `research-codebase` (Humanlayer, documentarian-not-critic stance) |

Plus the `deep-review` fold (already done): default scope = commits ahead of upstream + uncommitted changes; repo `REVIEW.md` overrides defaults; `(PRE-EXISTING)` tag for verified bugs the diff didn't introduce; cleanup findings point to `declutter`.

## Research grounding (done 2026-07-07)

- Humanlayer `research_codebase.md` fetched from github.com/humanlayer/humanlayer `.claude/commands/` — key judgment: document what IS, never critique; read mentioned files fully first; parallel locate→analyze; persistent frontmattered research doc with file:line refs; follow-ups append.
- `/security-review` prompt structure via Piebald-AI/claude-code-system-prompts: 5–6 vuln categories, a 17-item false-positive exclusion list, high-confidence-only reporting, exploit scenario mandatory.
- `/code-review` + `/simplify` semantics from code.claude.com/docs/en/code-review (v2.1.154 split: code-review = bug hunt, simplify = cleanup-only apply-fixes pass).

## Task status

- [x] **Batch A** — 6 SE-gap canonical skills + deep-review fold, propagated to all 5 compression surfaces (local/antigravity/gemini/cursor/AGENTS.md). Commit `a782f20`.
- [x] **Batch B** — 6 ops+navigation canonical skills. Commit `3ab523c`.
- [x] **Batch C** — 5 non-eng + research-codebase canonical skills. Committed with this doc.
- [x] **Batch D** — `skills-local/` compact variants for all 17 (match the imperative, "token usage is not a concern" style of existing local skills; report formats must match canonical).
- [x] **Batch E** — Antigravity: 17 workflows in `antigravity/workflows/` (frontmatter: `description:` only); `security.md` rule added (`trigger: model_decision`).
- [x] **Batch F** — Gemini: 17 TOML commands (`description` + `prompt = """..."""` + `{{args}}`); Cursor: `.mdc` rules covering the new areas (description/globs/alwaysApply frontmatter); AGENTS.md: new sections for the new areas.
- [x] **Batch G** — Docs & catalogs: root `README.md` (map counts + skills table), `skills/README.md` (catalog + composition + naming notes for `sec-audit`/`declutter`), `skills-local/README.md`, `ports/README.md`, `antigravity/README.md`, `ports/gemini/README.md`, `mcp-server/server.py` `route()` keyword hints for new skills, `PLAN.md` status log, this file's checkboxes.
- [x] **Improvement loop** — mechanical suite (frontmatter/name match, links, fences, TOML shape, doubled words, cross-surface drift grep) + full re-reads, scoped to new/touched files, fix+commit per pass, until 3 consecutive clean passes.
- [x] Update project memory file after completion.

## Conventions the new files must follow (learned from the existing loop)

- Frontmatter `name:` must equal directory name; description includes a "Use when…" sentence (it's the model-invocation trigger).
- Report lines use `SEVERITY [CONFIRMED|PLAUSIBLE] path:line — defect — trigger — fix` wherever findings are reported.
- Relative links must survive `install.sh` copying (skills are copied as standalone dirs — no repo-relative paths inside SKILL.md bodies; name skills by name, not path).
- Skills cross-reference each other by plain name (`prove`, `debug`) — those names exist in both profiles.
- Gemini TOML: exactly two `"""` fences, `description` key, `{{args}}` present.
- Local variants: numbered STEP structure, imperative voice, "token usage is not a concern", mandatory-minimum rules (e.g. "write at least 5 candidates").
- install.sh needs no changes — it globs directories/files.
- MCP server auto-discovers `skills/` and `skills-local/` — new skills appear automatically; only `route()` hints are manual.
