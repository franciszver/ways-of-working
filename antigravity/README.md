# antigravity/ — rules + workflows port

Ports of the library's canonical skills to Google Antigravity's `.agent/` format. Rules are the passive always-available layer; workflows are the slash-invoked procedures.

Format verified 2026-07 against [antigravity.google/docs/rules-workflows](https://antigravity.google/docs/rules-workflows) and community guides. If Antigravity has since changed frontmatter fields, check the official docs — the *content* here ports forward regardless.

## Install

```bash
# per project (versionable with the repo):
mkdir -p <project>/.agent
cp -r rules workflows <project>/.agent/

# or use ../install.sh --antigravity <project>
```

Global rules are managed through Antigravity's settings UI ("Manage Rules") — paste `rules/baseline.md` there to make the baseline apply everywhere.

## What's in the box

```
rules/
  baseline.md        trigger: always_on — the quality floor: verify-before-done,
                     read-before-edit, hypothesis debugging, honest reporting
  debugging.md       trigger: model_decision — full debug protocol, loads when a failure is being investigated
  reviewing.md       trigger: model_decision — verified-findings review protocol
  security.md        trigger: model_decision — high-confidence-only vuln reporting, loads for security-sensitive code
  testing.md         trigger: model_decision — bug-hunting test design
workflows/           slash-invoked: 26 commands
  Core:    /spec /architect /breakdown /debug /deep-review /prove /handoff /apply-working-process
  SE gaps: /sec-audit /perf /ci-triage /migrate /api-design /frontend-design /declutter
  Ops:     /incident /postmortem /release
  Nav:     /onboard /estimate /pr-workflow
  Other:   /data-analysis /brainstorm /explain /prompt-eng /research-codebase
```

## Design notes

- `always_on` is used exactly once (baseline) — always-on context is a tax on every request; the domain rules load via `model_decision` when their description matches the situation.
- Workflows deliberately contain no `// turbo` annotations (auto-run without approval). If you trust a step — e.g. the test-run steps in `/prove` — add `// turbo` on the line above it yourself.
- The `handoff` workflow + baseline rule implement the cross-tool continuity convention in [`../playbooks/HANDOFF.md`](../playbooks/HANDOFF.md): work started in Claude Code resumes here, and vice versa.
