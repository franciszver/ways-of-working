# antigravity/ — rules + workflows port

Ports of the library's canonical skills to Google Antigravity's format. Rules are the passive always-available layer. Workflows are thin stubs: each loads the matching canonical skill from `skills/` (installed alongside) rather than duplicating its content.

Format — last verified: see CHANGELOG — against [antigravity.google/docs/rules-workflows](https://antigravity.google/docs/rules-workflows) and community guides. If Antigravity has since changed frontmatter fields, check the official docs — the *content* here ports forward regardless.

## Install

```bash
./install.sh --antigravity <project>
```

Antigravity's docs say rules, workflows, and skills live under `.agents/`; older builds read `.agent/` (singular). Until a live install confirms which the running build reads (issue #11), `install.sh --antigravity` writes both `.agent/` and `.agents/`.

Global rules are managed through Antigravity's settings UI ("Manage Rules") — paste `rules/baseline.md` there to make the baseline apply everywhere.

## What's in the box

```
rules/
  baseline.md        trigger: always_on — the quality floor: verify-before-done,
                     read-before-edit, hypothesis debugging, honest reporting, STE prose style
  debugging.md       trigger: model_decision — full debug protocol, loads when a failure is being investigated
  reviewing.md       trigger: model_decision — verified-findings review protocol
  security.md        trigger: model_decision — high-confidence-only vuln reporting, loads for security-sensitive code
  testing.md         trigger: model_decision — bug-hunting test design
workflows/           slash-invoked: one thin stub per canonical skill (34), each pointing
                     at `.agents/skills/<name>/SKILL.md` (or `.agent/skills/<name>/SKILL.md`)
skills/               (installed by install.sh, not stored here) the 34 canonical skills, copied
                     from ../skills/ so Antigravity reads SKILL.md natively
```

Regenerate the workflow stubs from the canonical skills with `python3 scripts/gen-ports.py` (also regenerates the AGENTS.md skill pointers) — CI fails if they drift from `skills/`.

## Design notes

- `always_on` is used exactly once (baseline) — always-on context is a tax on every request; the domain rules load via `model_decision` when their description matches the situation. Cross-cutting floors (e.g. STE prose style) go inside baseline, not into a second always-on file.
- Workflows are stubs, not copies: each loads the matching `skills/<name>/SKILL.md` so the protocol lives in exactly one place. A workflow deliberately contains no `// turbo` annotations (auto-run without approval); add one yourself on a step you trust.
- The `handoff` workflow + baseline rule implement the cross-tool continuity convention in [`../playbooks/HANDOFF.md`](../playbooks/HANDOFF.md): work started in Claude Code resumes here, and vice versa.
