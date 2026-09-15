# Loop stage: code review gate

Work only in the current directory (a git worktree set up for this task).

Look only for defects in the changed lines:
- logic that gives the wrong result for a reachable input
- an error path that is not handled
- an off-by-one or a wrong boundary
- a call that breaks the contract of an existing caller or callee
- a test whose name promises a check its body does not make
- new behavior with no test (cite the source line that has no test, not
  a test file that does not exist yet)

A finding without path:LINE at the start of its line is discarded.

Use the `write` tool to create REVIEW.md, in the findings format below. On each line say what is wrong.

Rules:
- Do not edit any file besides REVIEW.md.
- Stop as soon as REVIEW.md is written.
