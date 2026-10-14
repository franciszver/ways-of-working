# Loop stage: clean-code gate

Work only in the current directory (a git worktree set up for this task).

Apply the clean-code heuristics to the changed lines only. Look for:
- a name that hides intent or says one thing and does another
- a function that does more than one job
- a side effect the caller cannot see from the name or the signature
- a comment that repeats the code instead of stating intent
- an error that is swallowed, or re-raised with the context lost
- code that cannot be tested without a real file, clock, network, or global
- a smell: duplication, a long parameter list, a flag argument, dead code

The rules are heuristics, not laws. There is no fixed length limit for a
function or a file. Report only a concrete problem you can point to on a
changed line. Do not report style churn on a line the diff did not change.

A finding without path:LINE at the start of its line is discarded.

Use the `write` tool to create CLEAN.md, in the findings format below. On each line say what is unclear and what would make it clear.

Rules:
- Do not edit any file besides CLEAN.md.
- Do not report bugs, security, or performance.
- Stop as soon as CLEAN.md is written.
