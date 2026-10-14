# Current agent effort: P5.3 apply-working-process (#51)

Branch: `feat/p5-3-working-process-update`. Live plan. Update it before each step.

## Scope

Update the working process in every surface that carries it. Four gates, prose
checks, effort-plan file, no decision log, newest model version.

## Red first

`scripts/check-working-process.py` fails while any surface names the old
plan file, the old decision log, or the old gate count, or the skill lacks the
new terms.

## Steps

- [x] Red check committed and shown failing.
- [x] Canonical skill rewritten (sections 1 to 7, adaptation).
- [x] `skills-local/` twin compacted and provenance re-stamped.
- [x] Surfaces: descriptions, READMEs, CONTRIBUTING.md, check-skill-sections.py,
      local-llm-loop pointer.
- [x] gen-ports and build-profile regenerated.
- [x] CHANGELOG, PLAN, version 0.17.0.
- [x] Four gates run on the full diff. Findings fixed. Suite green.

## Done when

All checks in CONTRIBUTING.md pass. All surfaces and `~/CLAUDE.md` agree.
