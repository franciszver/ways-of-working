# Loop stage: code review gate

Work only in the current directory (a git worktree set up for this task).

The diff under review is at the end of this prompt, with the latest
mechanical test run after it. You cannot read files: `write` is your
only tool. Judge the diff as given.

Look only for defects in the changed lines:
- logic that gives the wrong result for a reachable input
- an error path that is not handled
- an off-by-one or a wrong boundary
- a call that breaks the contract of an existing caller or callee
- a test whose name promises a check its body does not make
- new behavior with no test (cite the source line that has no test, not
  a test file that does not exist yet)

A finding without path:LINE at the start of its line is discarded.

Write REVIEW.md, in the findings format below. On each line say what is wrong.

Rules:
- Do not edit any file besides REVIEW.md.
- Stop as soon as REVIEW.md is written.
