# HANDOFF.md — session continuity across models and tools

The system-level companion to the `handoff` skill: how work moves between sessions, models, and environments without losing state. The skill (`skills/handoff/SKILL.md`) is the executable procedure for Claude Code; this playbook is the convention every environment shares, so a brief written in Claude Code resumes cleanly in Antigravity or a local-model session.

## The problem this solves

Context is expensive to build and impossible to transfer by default. Every session end, model switch, or tool switch silently discards: which requirements are done (with what evidence), which approaches were tried and failed, which decisions were made and why, and what the exact next action is. The handoff brief is the one file that carries all of it.

## The convention

- **One file per work stream**: `HANDOFF.md` at the repo root (or `.claude/HANDOFF.md` to keep it out of the way; gitignore by preference).
- **Updated in place** — current state only, never an append-only diary.
- **Written before quality degrades**, not after. A handoff written by an exhausted context inherits its confusion.
- Any agent in any environment picking up the work reads it first and maintains it after.

## The template

Mirrored in `skills/handoff/SKILL.md` — **keep the two in sync when editing either.**

```markdown
# Handoff: <task, one line>
Updated: <date> · State: <in progress | blocked | ready for review>

## Goal
<One sentence: what done looks like, and for whom/why.>

## Ledger
1. [DONE] <requirement> — evidence: <command + decisive output line>
2. [IN PROGRESS] <requirement> — exact state: <what's built, what's not>
3. [TODO] <requirement>
4. [BLOCKED] <requirement> — on: <precisely what unblocks it>

## Next action
<The single next step, executable without thinking:
"Run X. Expect Y. If Z instead, the cause is likely W — check path:line.">

## Decisions
- <decision> — because <reason>.

## Gotchas
- <what looked right but wasn't; flaky checks; invariants that must hold;
  refuted approaches a successor would plausibly retry, and why they fail>

## Map
- <file:line> — <what lives there / why it matters>
- Build: `<verbatim>` · Test: `<verbatim>` · Run: `<verbatim>`

## Verification state
I verified: <claims + evidence>. I did not verify: <claims + why>.
```

## Why this shape works for *cheap* successors

The brief is designed so a weaker model can execute well from it:

- **Ledger + Next action** remove interpretation — the two places small models fail hardest.
- **Decisions** prevent relitigating (small models happily rebuild what a big model deliberately chose).
- **Gotchas** transfer the expensive lessons — the tokens that cost the most to learn.
- **Verbatim commands** defeat the retyped-identifier corruption that plagues local models.

This is the mechanism behind ROUTING.md's downshift principle: frontier judgment gets serialized into a brief; cheap execution follows it.

## Resume protocol (any environment)

1. Read the whole brief.
2. **Spot-check the two or three cheapest load-bearing claims** — run the test claimed green, confirm pointers exist. A stale brief poisons everything built on it.
3. Execute the Next action; keep the ledger current as you work.
4. Don't undo recorded decisions without new evidence — disagree out loud instead.
5. On finishing or pausing: update the brief (or delete it when the stream is done and merged — a stale handoff is worse than none).

## Per-environment notes

- **Claude Code (frontier)**: `/handoff` skill writes it; the resume protocol is in the same skill.
- **Claude Code (local models)**: the `quality` skill's scratch-ledger feeds the brief; the global-local CLAUDE.md rules require writing it when stuck or stopping mid-task.
- **Antigravity**: the always-on baseline rule honors an existing `HANDOFF.md`; the `/handoff` workflow writes one.
- **Gemini CLI**: the `/handoff` command (ports/gemini) writes or resumes one.
- **Cursor**: the always-on baseline rule (ports/cursor) honors and updates it.
- **AGENTS.md tools / anything else**: the Session continuity section of the AGENTS.md port covers it — or paste the template; it's plain markdown by design.
