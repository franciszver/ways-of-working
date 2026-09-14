# Loop stage: fix

Work only in the current directory (a git worktree set up for this task).

Read FINDINGS.md, TEST_OUTPUT.txt, and HANDOFF.md here. If
NEEDS_HUMAN.md exists, read it too: it lists files an earlier fix stage
deleted and the driver restored. Do not delete them again.

Fix every finding FINDINGS.md lists, one finding per file write. If
FINDINGS.md says "no findings", make no code changes.

Rules:
- Before you stop, update HANDOFF.md so it reflects the current true
  state.
- Stop as soon as HANDOFF.md is written.
