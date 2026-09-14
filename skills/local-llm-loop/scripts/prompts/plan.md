# Loop stage: plan

Work only in the current directory (a git worktree set up for this task).

Read PLAN_INPUT.md here — it holds the task you must plan for.

Write PLAN.md: a numbered checklist of small steps. Size each step to one
file edit. Use this exact checkbox style so later stages can parse it:

    1. [ ] <step>
    2. [ ] <step>

Also write HANDOFF.md with this shape (fill in every block; keep it under
one page):

    # Handoff: <task, one line>
    Updated: <date> - State: in progress

    ## Goal
    <one sentence: what done looks like>

    ## Ledger
    1. [TODO] <requirement>
    2. [TODO] <requirement>

    ## Next action
    <the exact first PLAN.md step to execute>

    ## Decisions
    - none yet

    ## Gotchas
    - none yet

    ## Map
    - PLAN.md - the step checklist
    - Test: run the project's test command after every step

    ## Verification state
    I verified: nothing yet. I did not verify: the plan is untested.

Rules:
- Work in small steps.
- Write one file per turn.
- Run the project's test command after each write, if one exists.
- Never delete files.
- Never run git commands other than `git status` or `git diff`.
- Stop as soon as PLAN.md and HANDOFF.md are written.
