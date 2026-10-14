# Loop stage: plan

Work only in the current directory (a git worktree set up for this task).

Read PLAN_INPUT.md here — it holds the task you must plan for.

Write PLAN.md: a numbered checklist of small steps. Size each step to one
file edit. Use this exact checkbox style so later stages can parse it:

    1. [ ] <step>
    2. [ ] <step>

Name the failing test for a step by ending it with `| red: <what>`, where
<what> says which test or check must fail before the step is done:

    1. [ ] add parse_due() to dates.py | red: tests/test_dates.py rejects "tomorrow"

If a step has no test, such as a documentation edit, end it with
`| red: none`. A step with no `| red:` ending is allowed; the red stage
then picks the test itself.

Also write HANDOFF.md in the `handoff` skill's seven-block format (see
skills/handoff/SKILL.md) — one block per line, in this order: Goal,
Ledger, Next action, Decisions, Gotchas, Map, Verification state.

Rules:
- Stop as soon as PLAN.md and HANDOFF.md are written.
