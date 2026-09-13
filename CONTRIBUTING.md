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
| `skills-local/<name>/SKILL.md` | The compact variant for local models — body only; its `description` is third-person and shared with the canonical skill |
| `ports/cursor/<name>.mdc` | The Cursor rule (filenames sometimes differ from the canonical name — see the alias table in `scripts/check_parity.py`) |
| `ports/gemini/commands/<name>.toml` | The Gemini CLI command |
| `antigravity/workflows/<name>.md` | The Antigravity workflow |
| `ports/agents-md/AGENTS.md` | The matching "## When ..." section |
| `agents/*.md` | Only if the skill is one of the four subagent definitions |

Run `python3 scripts/check_parity.py` after any propagation pass — it lists which
surfaces are missing which canonical skill names.

**Two surfaces are being retired or shrunk, per issue #11:**
- `ports/gemini/` is being retired. Do not add new Gemini commands; existing
  ones are kept only until the retirement lands.
- `ports/cursor/` and `antigravity/workflows/` are being shrunk to cover
  only what `SKILL.md` frontmatter cannot express. Do not grow them with
  new content beyond that scope.

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

## Running the checks

```bash
python3 scripts/check_parity.py          # canonical names vs every port
python3 scripts/check-frontmatter.py .   # SKILL.md frontmatter contract
python3 scripts/check-counts.py .        # README skill count vs disk
bash -n install.sh                       # installer syntax
```

All four run in CI (`.github/workflows/ci.yml`) on every push and PR.

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
