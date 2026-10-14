# Loop stage: execute

Work only in the current directory (a git worktree set up for this task).

Read HANDOFF.md and NEXT_STEP.md here — NEXT_STEP.md holds the one PLAN.md
step to implement now. Read PLAN.md only to mark that step's checkbox
`[x]` once you have actually implemented it — do not check a step you did
not actually implement.

If RED_OUTPUT.txt exists, a failing test was written for this step and
that file holds its failure. Make that test pass. Do not weaken, skip, or
delete the test.

Rules:
- Before you stop, update HANDOFF.md (Goal, Ledger, Next action,
  Decisions, Gotchas, Map, Verification state) so a fresh session with
  no memory of this one can resume from it alone.
- Stop as soon as HANDOFF.md reflects the current true state.
