# Loop stage: red

Work only in the current directory (a git worktree set up for this task).

Read NEXT_STEP.md and HANDOFF.md here. NEXT_STEP.md holds the one PLAN.md
step the loop will implement next. Do not implement it now.

Write only the failing test or check for that step, and nothing else:
- If the step ends with `| red: <what>`, write that test or check.
- Otherwise write the smallest test that proves the step is done.
- Put the test where the project's test command will find it.
- The test must fail now, because the step is not implemented yet. It
  must fail for the right reason: a missing behavior, not a typo or a
  missing import in the test itself.

Rules:
- Do not touch source code, PLAN.md, or any test that already exists.
- Do not make the test pass. A later stage does that.
- The driver runs the test command after you stop. A test that passes
  fails this stage.
- Before you stop, update HANDOFF.md: name the new test under Ledger and
  say under Verification state that it should fail.
- Stop as soon as the test and HANDOFF.md are written.
