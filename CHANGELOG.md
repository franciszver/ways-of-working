# Changelog

All notable changes to this repo are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

- **Frontmatter profiles** (#12): `skills/` now carries only Agent Skills
  spec keys (`name`, `description`, `license`, `compatibility`,
  `metadata`, `allowed-tools`) — spec-portable across tools. A new
  `scripts/build-profile.py` generates `build/claude-code/`: canonical
  skills plus Claude-Code-only frontmatter from
  `scripts/profile-claude-code.yaml` (`argument-hint` for eight
  argument-taking skills; `context: fork` deliberately not used yet, its
  interaction with agents preloading the same skill is unverified), and a
  standalone plugin root so `.claude-plugin/marketplace.json` can offer
  `ways-of-working-claude-code` alongside the portable `ways-of-working`
  plugin. `build/claude-code/` is **committed**, like the antigravity
  stubs and `hooks/plugin-hooks.json` — `scripts/build-profile.py .
  --check` (no writes) is the CI drift gate, and it also enforces the
  frontmatter contract on the generated tree and rejects a profile entry
  with a disallowed key, an unknown skill name, or a key already present
  in that skill's canonical frontmatter. `install.sh --claude-user`/
  `--claude-project` (frontier profile) and `--check` read the committed
  tree directly — no Python required to install. Considered and reverted
  adding `allowed-tools: Read, Grep, Glob, Bash` to `deep-review`,
  `sec-audit`, `research`, `research-codebase`: the key pre-approves
  tools for the turn without restricting anything else, so pre-approving
  `Bash` on skills that read untrusted repos and diffs would remove the
  one permission prompt standing between prompt injection in that content
  and command execution. `agents/*.md`'s `disallowedTools` already
  enforces read-only for the review agents.

- **Ports** (#11): retired the Gemini port — `ports/gemini/README.md`
  now points the paid-tier Gemini CLI at `install.sh --skills
  ~/.gemini/skills` (free tier retired 2026-06-18 for Antigravity CLI).
  Shrank Cursor's port to `baseline.mdc` (folded in `ste-writing.mdc`),
  `testing.mdc`, and `frontend-design.mdc` — Cursor reads `skills/`
  natively (`install.sh --skills <repo>/.cursor/skills`); fixed
  `testing.mdc`'s glob to drop spaces after commas. Replaced every
  Antigravity workflow with a thin stub that loads its matching skill,
  added the 7 missing stubs, and added `scripts/gen-ports.py` to
  regenerate the stubs and the AGENTS.md skill pointers from
  `skills/*/SKILL.md` (CI checks for drift and pointer uniqueness).
  Rewrote `AGENTS.md` as the single portable entry point: a compact
  always-on floor plus one `@skills/<name>/SKILL.md` pointer per
  canonical skill. `install.sh --antigravity` writes the real rules,
  workflows, and skills once under `.agents/` and symlinks `.agent/`
  to it (or writes into `.agent/` too if it is already a real
  directory), so either build Antigravity ships reads the same files
  — see `antigravity/README.md` for the rationale. `install.sh
  --agents-md` now also installs `skills/` alongside `AGENTS.md` so
  its pointers resolve. Added `install.sh --skills DIR` for any tool
  that reads Agent Skills natively, guarded against copying a skill
  onto itself and against a destination inside the library.
  `scripts/check_parity.py` dropped the gemini, antigravity, and
  agents-md surfaces (the generated ones are checked more strongly by
  `gen-ports.py --check`) and the cursor per-skill check (cursor now
  checks its exact file set); `scripts/parity-allow.txt` keeps only
  the `skills-local` gap (#10).
- **Agents, hooks, CLAUDE.md** (#9): agents gain `skills:` preload
  (code-reviewer→`deep-review`, verifier→`prove`, researcher→`research`,
  architect→`architect`) and `disallowedTools: [Edit, Write, NotebookEdit]`
  on code-reviewer/verifier (kept independent of `tools:` as a guard
  against `tools:` being widened later); `maxTurns: 40` on researcher,
  `effort: high` on architect; bodies trimmed to role/tool-budget/output-
  format (≤40 lines, enforced by new `scripts/check-agents.py`). Hooks:
  `format-on-stop.sh` also runs on `SubagentStop`; a new opt-in
  `failure-counter.sh` (per-project via `install.sh --hooks`, not shipped
  by the plugin) runs on `PostToolUseFailure`, logs to
  `.claude/failure-log` (gitignored), and reminds Claude after two
  consecutive failures of the same command via `additionalContext`/
  `systemMessage`. `guardrails.sh`/`test-gate.sh` now emit the documented
  `hookSpecificOutput.permissionDecision` JSON on stdout (exit 2 stays as
  fallback) via a shared `hooks/scripts/_hook_lib.sh`, and `test-gate.sh`
  runs the test command as `bash -o pipefail -c` so a piped command's
  real failure is caught. `claude-md/global-frontier.md` and
  `global-local.md` shrink to an always-on core; `claude-md/rules/
  {debugging,code-changes,prose-style}.md` carry the rest, `code-changes.md`
  scoped with memory-doc `paths:` frontmatter, and `install.sh` installs
  them into `.claude/rules/`.
- **Release**: `.claude-plugin/plugin.json` version bumped to `0.5.0` —
  `agents/` and `hooks/` changed in this PR.
- **Skills** (#7): deduplicated and layered canonical skills for progressive
  disclosure. `lean-max-effort` cut from 95 to 55 lines — kept the
  four-phase frame, replaced restated `spec`/`prove`/`debug` content with
  one-line pointers. `plain-language` dropped its inline Vocabulary/
  Constructions copies of `references/`, and now states its last-refreshed
  and refresh-due dates near the top (refresh is overdue — separate task).
  `apply-working-process` moved its two dated `(Observed …)` evidence
  bullets in §7 into a new `references/observations.md`, replaced with
  ≤20-word rules. `demo-video` gained a runnable
  `scripts/build_demo.py` (screenshots → captioned frames → mp4 + gif,
  stdlib-only soundtrack) and a `references/pipeline.md`; the body now
  states judgment plus a new `## Anti-patterns`. `deep-review` now defines
  review scope once; `declutter` points at it instead of repeating it.
  Standardized every skill's closing section to `## Rules` and/or
  `## Anti-patterns`, and added `## Report` to `incident`, `postmortem`,
  `prove`, `research`, `spec`, `refactor`, `release`. Added
  `scripts/check-skill-sections.py` (closing-section spelling, required
  `## Report` sections, duplicate-paragraph check) to CI and
  `CONTRIBUTING.md`. Fix round from review: the duplicate check now uses
  12-word-shingle Jaccard overlap (catches paraphrases, not just
  byte-identical text) instead of exact-paragraph matching; the section
  check validates every `##` heading, not just the last; restored two
  `apply-working-process` working-norm bullets and two `lean-max-effort`
  lines a prior pass had dropped; `plain-language` ran its own refresh
  procedure (Wikipedia re-cached, `ai-tells.md` refreshed in degraded
  mode after Forbes returned 403) and now keeps one authoritative refresh
  date instead of two; `deep-review`'s REVIEW.md-override sentence
  de-duplicated; `demo-video/scripts/build_demo.py` now uses a single
  temp directory for all intermediates, drops the dead `--no-music` flag
  and unused `caption_list`, and wraps overlong captions instead of
  clipping them.
- **Release**: `.claude-plugin/plugin.json` version bumped to `0.6.0` —
  `skills/` changed in this PR, and plugin installs only update on a
  version bump (see `CONTRIBUTING.md`'s Releasing section).
- **Skills** (#6): rewrote skill descriptions in third person, dropped
  imperative openers and "always on" phrasing, added a description lint
  to `check-frontmatter.py`, and added task-shaped triggers plus
  disambiguation clauses for overlapping pairs (`research`/
  `research-codebase`, `debug`/`ci-triage`, `explain`/`write`). Moved
  the "always on" statements for `apply-working-process`,
  `lean-max-effort`, and `ste-writing` into `claude-md/global-frontier.md`
  and `claude-md/global-local.md`. Propagated the changed descriptions to
  `skills-local/` where the same skill exists.
- **Release**: `.claude-plugin/plugin.json` version bumped to `0.3.0` —
  `skills/` changed in this PR, and plugin installs only update on a
  version bump (see `CONTRIBUTING.md`'s Releasing section).
- **Fix (#5)**: MCP server `route()` regex bugs fixed — `PR`, `CI`, `down`,
  `ui`, `ux`, and `css` no longer match inside unrelated words (e.g. "prove",
  "cite", "download"). Every canonical skill now has a route hint mentioning
  it by name. Pure logic (skill discovery, route matching) split into
  `mcp-server/library.py`, which has no `mcp` import, so
  `mcp-server/test_library.py` runs without the `mcp` package installed;
  `mcp-server/test_server.py` covers the MCP-wired server and skips itself
  when `mcp` isn't installed. Frontmatter parsing is now shared between
  `mcp-server/library.py` and `scripts/check-frontmatter.py` via a new
  `scripts/_lib.py::parse_frontmatter`. The server's `instructions` text is
  generated from `discover_skills()` instead of a hand-maintained count and
  name list, and the server now refuses to start on an empty skill catalog
  instead of serving an empty blurb. `pyproject.toml` dropped
  `[build-system]`/`[project.scripts]` (the console script was unused and a
  wheel build would ship no skills) and gained a `pyyaml` dependency.
  `mcp-server/README.md` and `install.sh`'s `--mcp` output now use the same
  registration invocation, relying on the project's own `mcp`/`pyyaml`
  dependencies instead of `--with`. CI runs the mcp-server tests twice —
  once with `mcp` absent (proving the import boundary) and once installed.
- **Release**: `.claude-plugin/plugin.json` version bumped to `0.2.0` —
  `hooks/` changed in that PR, and plugin installs only update on a
  version bump (see `CONTRIBUTING.md`'s Releasing section).
- **Security**: the Claude Code plugin manifest excludes `test-gate.sh` and
  `format-on-stop.sh` (`scripts/merge-hooks.py --emit-plugin`) — a plugin
  hook fires in every project opened with no per-project opt-in.
  `test-gate.sh` runs the first line of the repo-controlled
  `.claude/test-command` as a shell command; `format-on-stop.sh` runs
  `npx --no-install prettier`, which resolves the *project's*
  `node_modules/.bin`. Either would let a cloned malicious repo run
  arbitrary code. Both stay available per-project, opt-in, via
  `install.sh --hooks`; the plugin ships only `guardrails.sh`.
- **Rename**: every reference to the repo's old model-branded name
  replaced with `ways-of-working` (MCP server name, pyproject, env var
  `WAYS_OF_WORKING_LIBRARY`, install guard comments, docs). README
  reframed as process-not-model; `PLAN.md` marked historical (#3).
- **Distribution, CI, hygiene** (#4): `.claude-plugin/plugin.json` and
  `marketplace.json` so Claude Code can install this library as a plugin;
  `install.sh` gained `--link` (symlink installs), `--check` (drift
  detection), a profile marker with refuse/force semantics, a fixed
  `usage()` that prints the full header, and automatic hooks merging into
  an existing `settings.json`; CI now runs a port-parity check, a
  SKILL.md frontmatter check, and a README skill-count check on every
  push and PR; `CONTRIBUTING.md` added; README skill count corrected to
  34, generated by `scripts/check-counts.py` rather than typed by hand.
