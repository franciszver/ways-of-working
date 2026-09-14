# Loop stage: execute

Work only in the current directory (a git worktree set up for this task).

Read HANDOFF.md and PLAN.md here.

Implement the next unchecked step(s) in PLAN.md. After a step is done,
mark its checkbox `[x]` in PLAN.md — do not check a step you did not
actually implement.

Rules:
- Work in small steps, one file write per turn.
- Run the project's test command after each write, if one exists.
- Never delete files.
- Never run git commands other than `git status` or `git diff`.
- Before you stop, update HANDOFF.md (Goal, Ledger, Next action,
  Decisions, Gotchas, Map, Verification state) so a fresh session with
  no memory of this one can resume from it alone.
- Stop as soon as HANDOFF.md reflects the current true state.
