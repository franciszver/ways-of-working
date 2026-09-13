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

### skills-local provenance markers

`scripts/check_parity.py` checks each canonical-backed
`skills-local/<name>/SKILL.md` twin for a provenance marker right after its
frontmatter:

```
<!-- local: derived-from: skills/<name>/SKILL.md@<sha256 of that file, first 12 hex> -->
```

A twin with no marker fails as `MISSING PROVENANCE`. A twin whose marker's
hash no longer matches the canonical file's current hash fails as `STALE`
— canonical changed since the twin was last derived, so the twin needs a
fresh look, not just a fresh hash. Run
`python3 scripts/stamp-provenance.py <name>` (or `--all`) after re-deriving
a twin, or any time canonical changes underneath it, to write the current
hash — it computes the hash for you, so re-deriving never means hand-typing
one.

This replaced an earlier heading-set comparison: the file-level waiver it
needed ended up on 22 of 29 twins (nearly the whole pack, since the compact
house style renames or merges canonical headings by design), a fenced code
block's example lines were being counted as real headings, and the check
still could not see drift inside a heading that stayed present. A content
hash sees any drift, in a heading or not, and asks for a look rather than
silently waiving it.

A twin that deliberately diverges from canonical — not silently drops a
rule, but chooses differently on purpose — may still carry, alongside its
provenance marker, a free-text note:

```
<!-- local: deliberate divergence: <reason> -->
```

This is informational only; `check_parity.py` never reads it and it waives
nothing. It exists so a reader hits the reason next to the difference
instead of wondering whether the twin drifted by accident.

### The parity allowlist

A canonical skill with no `skills-local/` twin at all is listed in
`scripts/parity-allow.txt` as `skills-local:<name>:<reason>` — the parser
rejects a line with no reason (or a blank one), so a bare name is never a
silent pass. State the real criterion: token discipline that only makes
sense on a token-scarce model, a reference list too large or too volatile
to fit the line budget, or judgment (weighing tradeoffs, sources, or
dependencies) that a compact directive body would flatten instead of apply.
"Routes to a paid tier" is not by itself a reason — `playbooks/ROUTING.md`
groups some skills that got a local variant with some that didn't in the
same routing row, so tier alone doesn't explain a gap. Close a gap by
writing the compact variant and deleting its allowlist line, not by leaving
both in place.

## The frontmatter contract

Every `skills/**/SKILL.md` and `skills-local/**/SKILL.md` must have YAML
frontmatter with:

- `name` matching its directory name exactly.
- A non-empty `description` under 1,024 characters.
- No key outside the Agent Skills spec set: `name`, `description`,
  `license`, `compatibility`, `metadata`, `allowed-tools`.

A file that must carry a non-spec key (for example, a Claude-Code-only
`disable-model-invocation`) is listed in `scripts/frontmatter-allow.txt`
with a comment pointing at this section, not silently exempted.
`skills-local/iterate/SKILL.md` is the current example: `skills-local/` is
Claude-Code-only by construction (see "Two profiles" below), so its
non-spec keys stay inline rather than moving through the profile
mechanism, which only reads canonical `skills/`.

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

`disallowedTools` is required on `code-reviewer` and `verifier` independent
of their `tools:` list — it's a guard against `tools:` being widened later
without someone noticing the agent could then edit code. `memory:` (subagent
persistent memory) is deliberately not set on either agent: the memory docs
say enabling it auto-enables Read/Write/Edit for the agent's own memory
files, which would collide with `disallowedTools` on a read-only reviewer.

## CLAUDE.md and path-scoped rules

`claude-md/global-frontier.md` and `global-local.md` carry only the
always-on core (rules that must apply in every session regardless of what
files are touched). Guidance that only matters for certain file types lives
in `claude-md/rules/*.md` instead. `code-changes.md` is scoped with the
memory doc's `paths:` frontmatter (see
[the memory docs](https://code.claude.com/docs/en/memory#path-specific-rules));
`debugging.md` and `prose-style.md` carry no `paths:` and load
unconditionally — prose style governs commits, PR text, and replies, none
of which are files Claude reads, so a path scope would miss most of what it
governs. `install.sh --claude-user` and `--claude-project` install
`claude-md/rules/*.md` into `.claude/rules/` alongside the core file
(`--claude-project` always copies, never symlinks, since the memory docs
treat an out-of-tree symlinked rule as an external import and drop its
`paths:` scoping). Add a new rule file, not a new paragraph in the core,
when guidance is specific to a file type or directory.

## Two profiles: portable skills/, committed Claude Code profile

`skills/` is spec-portable by rule — it never carries a Claude-Code-only
key, even for a skill Claude Code alone runs. A key such as
`argument-hint` goes in `scripts/profile-claude-code.yaml` instead, keyed
by skill name. Allowed profile keys: `context`, `agent`, `argument-hint`,
`disable-model-invocation`, `user-invocable`, `model`, `effort`. A key
outside that set, a skill name outside canonical `skills/`, or a key that
already exists in that skill's canonical frontmatter is a hard error from
`scripts/build-profile.py`.

`context: fork` is not used in the current profile: its interaction with
`agents/*.md` entries that already preload the same skill is unverified
— it may require an explicit `agent:` key, or nest forks. Follow-up once
checked in a live session.

`scripts/build-profile.py` reads `scripts/profile-claude-code.yaml` and
writes `build/claude-code/skills/<name>/SKILL.md` for every canonical
skill: the canonical frontmatter plus that skill's extra keys, body
unchanged. It also writes `build/claude-code/` as a standalone plugin
root (its own `.claude-plugin/plugin.json`, `agents/`, `hooks/`) — a
plugin's own `./skills` is always scanned by default and the manifest's
`skills` field only adds directories, so the enhanced profile needs its
own plugin root rather than an entry on the existing `plugin.json`.

`build/claude-code/` is **committed**, the same way the antigravity stubs
and `hooks/plugin-hooks.json` are — not generated at install or CI time.
After any change to a canonical skill or to
`scripts/profile-claude-code.yaml`, run `python3 scripts/build-profile.py
.` and commit the result; `python3 scripts/build-profile.py . --check`
(no writes) is the drift gate CI runs. `install.sh --claude-user`/
`--claude-project` (frontier profile) and `--check` read the committed
tree directly — no Python needed to install.

## Running the checks

```bash
python3 scripts/check_parity.py          # canonical names/provenance vs skills-local + cursor's exact file set
python3 scripts/gen-ports.py . --check   # antigravity stubs + AGENTS.md pointers vs skills/ (drift + uniqueness)
python3 scripts/build-profile.py . --check  # build/claude-code/ vs skills/ + profile-claude-code.yaml (drift + contract)
python3 scripts/check-frontmatter.py .   # SKILL.md frontmatter contract
python3 scripts/check-counts.py .        # README skill count vs disk
python3 scripts/check-agents.py .        # agents/*.md frontmatter contract
python3 scripts/check-skill-sections.py . # closing sections, ## Report, duplicate paragraphs, dangling references
bash scripts/test-install.sh             # installer behavior (also runs bash -n)
```

After changing a canonical skill or `scripts/profile-claude-code.yaml`,
run `python3 scripts/build-profile.py .` (writes) first, commit
`build/claude-code/`, then run the `--check` above.

All of these run in CI (`.github/workflows/ci.yml`) on every push and PR.

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
