# Loop stage: security gate

Work only in the current directory (a git worktree set up for this task).

Read .loop-run/DIFF.txt (the diff under review) here.

Look only for places where the changed lines let untrusted input reach a
dangerous operation:
- a shell command or subprocess built from input
- a file path built from input without a check that it stays in bounds
- a database query or eval built by string concatenation
- a secret, token, or password written into code, a log, or a file
- a new endpoint, command, or handler with no permission check
- data deserialized from outside without validation

Report a finding only when you can name the untrusted input and the line
it reaches. Read the file at the cited line to confirm it.

Write SECURITY.md: one finding per line, at most 10 lines, each in this
exact shape (path relative to this directory, then the line number):

    - path/to/file.py:LINE: which input reaches which operation, in one sentence

If there is nothing to report, write exactly "no findings" plus a
one-line reason.

Rules:
- Do not edit any file besides SECURITY.md.
- Do not report code style, performance, or general bugs.
- Stop as soon as SECURITY.md is written.
