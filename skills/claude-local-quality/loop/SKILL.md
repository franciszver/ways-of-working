---
name: loop
description: Explicit critique-and-revise quality loop, run on demand. Re-reads the actual files from disk, attacks them as a hostile reviewer, fixes what it finds, verifies, and repeats until acceptance criteria pass or the round budget is spent. Invoked by the user as /loop [rounds] [focus].
disable-model-invocation: true
argument-hint: "[rounds] [focus, e.g. 'error handling']"
---

# /loop — iterate until it is actually good

Arguments: "$ARGUMENTS"

- If the first token is an integer, it is the round budget (default 2, max 5). Everything after it is the review focus.
- No arguments → review the most recent work in this conversation with a budget of 2.
- If the arguments describe a brand-new task instead of a focus, perform the task under the `quality` skill workflow first, then run this loop on the result.

The user runs this command because the current state is not good enough yet. Do not soften findings to finish early — the entire value of this command is in the extra rounds. Token usage is not a concern.

## Each round

**1. Criteria.** Reconstruct what the work is supposed to do from the conversation and write 3–7 acceptance criteria. Each must be objectively checkable ("handles empty input without a traceback", "all three endpoints return the documented schema"). If the user gave a focus, at least two criteria must target it. Print the list in round 1; reuse it afterward.

**2. Attack.** Switch roles: you are a hostile senior reviewer paid per real defect. Re-read the actual current files from disk — reviewing your memory of them finds nothing. Hunt specifically for:

- invented or unverified APIs, imports, and config keys
- unhandled failures: empty/None input, missing file, bad encoding, network error, concurrent access
- off-by-one and boundary conditions
- requirements silently dropped or quietly reinterpreted
- code paths never executed by any check
- resource leaks, swallowed exceptions, secrets or debug prints left in code

Report each finding as `SEVERITY path:line — issue — fix` with severity BLOCKER, MAJOR, or MINOR. Zero findings in round 1 usually means the review was shallow — re-check the error paths before concluding that.

**3. Fix.** Apply every BLOCKER and MAJOR fix, and MINOR fixes when cheap. Complete code only — never stubs, ellipses, or "rest unchanged" placeholders.

**4. Verify.** Run the strongest available check: tests, build, or executing the code on realistic input. Quote the decisive output line verbatim.

**5. Score.** Mark each acceptance criterion PASS or FAIL with one line of evidence. All PASS → stop early and report.

## Final report

- One line per round: defects found / fixed, verification result.
- The criteria checklist with final PASS/FAIL marks.
- Remaining known issues and anything still unverified, stated plainly with "I verified …" / "I did not verify …".
