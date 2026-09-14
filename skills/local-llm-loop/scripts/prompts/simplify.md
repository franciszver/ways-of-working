# Loop stage: simplify gate

Work only in the current directory (a git worktree set up for this task).

Read .loop-run/DIFF.txt (the diff under review) and TEST_OUTPUT.txt (the
latest mechanical test run) here.

Look only for behavior-preserving cleanups inside the changed lines:
- duplicated logic that a helper already in this repo provides
- dead code the diff added: unused variables, imports, functions, branches
- needless indirection: a wrapper or layer that adds nothing
- code at the wrong altitude: a low-level detail inside a high-level
  function, or the reverse

Before you list a finding, read the file at the cited line to confirm it.

Write SIMPLIFY.md, in the findings format below. On each line say what to change.

Rules:
- Do not edit any file besides SIMPLIFY.md.
- Do not report style preferences. Do not report bugs; a later gate
  covers those.
- Stop as soon as SIMPLIFY.md is written.
