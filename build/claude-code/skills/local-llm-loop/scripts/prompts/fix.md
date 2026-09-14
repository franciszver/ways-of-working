# Loop stage: fix

Work only in the current directory (a git worktree set up for this task).

Read REVIEW.md, TEST_OUTPUT.txt, and HANDOFF.md here.

Fix every defect REVIEW.md lists. If REVIEW.md says "no findings", make
no code changes.

Rules:
- Work in small steps, one file write per turn.
- Run the project's test command after each write, if one exists.
- Never delete files.
- Never run git commands other than `git status` or `git diff`.
- Before you stop, update HANDOFF.md so it reflects the current true
  state.
- Stop as soon as HANDOFF.md is written.
