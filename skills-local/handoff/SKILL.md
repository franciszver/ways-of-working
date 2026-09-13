---
name: handoff
description: Writes a compact continuation brief so a fresh session — or a cheaper model — resumes exactly where this one left off, without re-deriving anything. Use when context is running long, when ending a session mid-task, when downshifting work to a smaller model, or when delegating a subtask. Also defines how to RESUME from a handoff.
---

<!-- local: derived-from: skills/handoff/SKILL.md@1ff5b9bebeef -->

# Handoff Protocol

## When to write one
Context running long · session ends mid-task · work downshifts to a cheaper model · a subtask is delegated.

## Where
One file, updated in place — `HANDOFF.md` at repo root (or `.claude/HANDOFF.md`, gitignored if noisy). Never append a diary.

## The brief — seven blocks, ≤ one page

```markdown
# Handoff: <task, one line>
Updated: <date> · State: <in progress | blocked | ready for review>
## Goal
<one sentence: what done looks like, for whom/why>
## Ledger
1. [DONE] <requirement> — evidence: <command + decisive output line>
2. [IN PROGRESS] <requirement> — exact state
3. [TODO] <requirement> · 4. [BLOCKED] <requirement> — on: <what unblocks it>
## Next action
<single next step, executable without thinking>
## Decisions
- <decision> — because <reason>
## Gotchas
- <traps, flaky checks, invariants, refuted approaches and why they fail>
## Map
- <file:line> — <why it matters> · Build/Test/Run: `<verbatim commands>` · Branch: `<name>` · Working tree: `<clean | N dirty | stashed>` · PR: `<link | "none yet">`
## Verification state
I verified: <claims + evidence>. I did not verify: <claims + why>.
```

## Quality bar and rules
Could you resume cold from only this file in a month? Density beats completeness — pointers over pasted content. Commands and identifiers VERBATIM from tool output, never retyped from memory. No journey narrative except refuted approaches under Gotchas. Write it before quality degrades, not after.

## Resuming from a handoff
Read the whole brief, spot-check 2–3 cheap load-bearing claims before trusting it, execute the Next action, keep the ledger current, and never relitigate a recorded decision without new evidence.
