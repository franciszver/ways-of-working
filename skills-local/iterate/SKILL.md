---
name: iterate
description: Explicit critique-and-revise quality loop, run on demand. Re-reads the actual files from disk, attacks them as a hostile reviewer, fixes what it finds, verifies, and repeats until acceptance criteria pass or the round budget is spent. Invoked by the user as /iterate [rounds] [focus].
disable-model-invocation: true
argument-hint: "[rounds] [focus, e.g. 'error handling']"
---

# /iterate — run the quality loop again, on demand

Arguments: "$ARGUMENTS"

Run the `quality` skill's **Phase 4 — LOOP** exactly as written there, with two overrides: the round cap is the first integer in the arguments (default 2, max 5) instead of 3, and if a focus follows it, at least two acceptance criteria must target that focus. If the first token is an integer, it is the round budget; everything after it is the focus. No arguments → attack the most recent work in this conversation with a budget of 2. If the arguments describe a brand-new task instead of a focus, run the full `quality` workflow on it first, then loop it. Token usage is not a concern.
