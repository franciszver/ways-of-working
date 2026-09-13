# Contributing to ways-of-working

This file explains how to change a canonical skill, what the frontmatter
contract requires, how to run the checks, and the three gates every PR
passes before merge.

## Propagating a canonical skill change

`skills/` is the source of truth. A change to a canonical skill's judgment
(a new rule, a changed threshold, a renamed concept) must propagate to
every surface that carries a compression of it:

| Surface | What to update |
|---|---|
| `skills-local/<name>/SKILL.md` | The compact variant for local models — body only; its `description` is third-person and shared with the canonical skill (a deliberate subset, not every canonical skill has one — see `scripts/parity-allow.txt`) |
| `antigravity/workflows/<name>.md` | Nothing by hand — run `python3 scripts/gen-ports.py`, which regenerates the stub's `description:` from `skills/<name>/SKILL.md` |
| `ports/agents-md/AGENTS.md` | Nothing by hand for the skill pointer line — the same `gen-ports.py` run regenerates it; edit the file directly only for its always-on floor |
| `agents/*.md` | Only if the skill is one of the four subagent definitions; each preloads its matching skill's full text |

`ports/cursor/` is not per-skill: it carries only the always-on floor
(`baseline.mdc`) plus two glob-scoped rules `SKILL.md` cannot express
(`testing.mdc`, `frontend-design.mdc`). Cursor and the paid-tier Gemini CLI
read `skills/` natively (`install.sh --skills <dest>`); `ports/gemini/`
carries only a README pointer, not commands.

Run `python3 scripts/check_parity.py` and `python3 scripts/gen-ports.py --check`
after any propagation pass — together they cover every surface.

## The frontmatter contract

Every `skills/**/SKILL.md` and `skills-local/**/SKILL.md` must have YAML
frontmatter with:

- `name` matching its directory name exactly.
- A non-empty `description` under 1,024 characters.
- No key outside the Agent Skills spec set: `name`, `description`,
  `license`, `compatibility`, `metadata`, `allowed-tools`.

A file that must carry a non-spec key (for example, a Claude-Code-only
`disable-model-invocation`) is listed in `scripts/frontmatter-allow.txt`
with a comment pointing at the tracking issue, not silently exempted.

## The agent contract

Every `agents/*.md` preloads its matching skill via `skills:` frontmatter
instead of restating that skill's doctrine in its body — the skill is the
single source of truth, and the agent body stays limited to role, tool
budget, and output format (40 lines or fewer). `code-reviewer` and
`verifier` must also declare `disallowedTools: [Edit, Write, NotebookEdit]`,
since neither ever modifies code. `scripts/check-agents.py` enforces all of
this: a `skills:` entry that names a skill absent from `skills/` fails the
check, as does a body over 40 lines or a missing `disallowedTools` entry on
the two review agents.

## CLAUDE.md and path-scoped rules

`claude-md/global-frontier.md` and `global-local.md` carry only the
always-on core (rules that must apply in every session regardless of what
files are touched). Guidance that only matters for certain file types
lives in `claude-md/rules/*.md` instead, scoped with the memory doc's
`paths:` frontmatter (see
[the memory docs](https://code.claude.com/docs/en/memory#path-specific-rules)).
`install.sh --claude-user` and `--claude-project` install `claude-md/rules/*.md`
into `.claude/rules/` alongside the core file. Add a new rule file, not a
new paragraph in the core, when guidance is specific to a file type or
directory.

## Running the checks

```bash
python3 scripts/check_parity.py          # canonical names vs skills-local + cursor's exact file set
python3 scripts/gen-ports.py . --check   # antigravity stubs + AGENTS.md pointers vs skills/ (drift + uniqueness)
python3 scripts/check-frontmatter.py .   # SKILL.md frontmatter contract
python3 scripts/check-counts.py .        # README skill count vs disk
python3 scripts/check-agents.py .        # agents/*.md frontmatter contract
bash -n install.sh                       # installer syntax
```

All five run in CI (`.github/workflows/ci.yml`) on every push and PR.

## The three gates

Before any PR merges, run on the full diff, in order:

1. **Simplify** (`/simplify` or the `declutter` skill) — cleanup only, no
   redesign.
2. **Security review** (`/security-review` or the `sec-audit` skill).
3. **Code review** (`/code-review` or the `deep-review` skill).

Fix every finding — do not defer a real defect to a follow-up issue. Re-run
the test suite green after the fixes, including on docs-only PRs.

## Releasing

Plugin installs (`claude plugin install`) only pull an update when
`.claude-plugin/plugin.json`'s `version` changes. Whenever a PR changes
`skills/`, `agents/`, or `hooks/`, bump that `version` and add a
`CHANGELOG.md` entry in the same PR — CI fails a pull request that touches
those paths without a version bump (see `.github/workflows/ci.yml`).

## Commits and PRs

- Conventional commit messages (`feat:`, `fix:`, `docs:`, `test:`, `ci:`).
- Add an `Assisted-by: Claude Code` trailer when an AI assisted the commit.
- One issue = one branch = one PR; the PR body ends with `Closes #N`.
- Red first: commit the failing check before the change that makes it pass.
