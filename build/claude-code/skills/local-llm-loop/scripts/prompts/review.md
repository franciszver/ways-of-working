# Loop stage: code review gate

Work only in the current directory (a git worktree set up for this task).

Read .loop-run/DIFF.txt (the diff under review) and TEST_OUTPUT.txt (the
latest mechanical test run) here.

Look only for defects in the changed lines:
- logic that gives the wrong result for a reachable input
- an error path that is not handled
- an off-by-one or a wrong boundary
- a call that breaks the contract of an existing caller or callee
- a test whose name promises a check its body does not make
- new behavior with no test

Before you list a finding, read the file at the cited line to confirm it.

Write REVIEW.md: one finding per line, at most 10 lines, each in this
exact shape (path relative to this directory, then the line number):

    - path/to/file.py:LINE: what is wrong, in one sentence

If you find nothing wrong, write exactly "no findings" plus a one-line
reason.

Rules:
- Do not edit any file besides REVIEW.md.
- Stop as soon as REVIEW.md is written.
