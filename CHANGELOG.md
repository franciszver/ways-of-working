# Changelog

All notable changes to this repo are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

- **Ports** (#11): retired the Gemini port — `ports/gemini/README.md`
  now points the paid-tier Gemini CLI at `install.sh --skills
  ~/.gemini/skills` (free tier retired 2026-06-18 for Antigravity CLI).
  Shrank Cursor's port to `baseline.mdc` (folded in `ste-writing.mdc`),
  `testing.mdc`, and `frontend-design.mdc` — Cursor reads `skills/`
  natively (`install.sh --skills <repo>/.cursor/skills`); fixed
  `testing.mdc`'s glob to drop spaces after commas. Replaced every
  Antigravity workflow with a 5-line stub that loads its matching
  skill, added the 7 missing stubs, and added `scripts/gen-ports.py`
  to regenerate the stubs and the AGENTS.md skill pointers from
  `skills/*/SKILL.md` (CI checks for drift). Rewrote `AGENTS.md` as
  the single portable entry point: a 33-line always-on floor plus one
  `@skills/<name>/SKILL.md` pointer per canonical skill (8026 bytes).
  `install.sh --antigravity` now writes rules, workflows, and skills to
  both `.agent/` and `.agents/` until a live install confirms which the
  running build reads. Added `install.sh --skills DIR` for any tool
  that reads Agent Skills natively. `scripts/check_parity.py` dropped
  the gemini surface and the cursor per-skill check (cursor now checks
  its exact file set); `scripts/parity-allow.txt` keeps only the
  `skills-local` gap (#10).
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
