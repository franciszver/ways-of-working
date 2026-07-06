---
name: quality
description: Mandatory quality workflow for ALL coding and agentic work — writing or editing code, debugging, refactoring, planning, running tools, or producing any technical result. Use this skill on EVERY non-trivial task, even when the user does not mention quality, testing, or review. It enforces plan-before-act, verify-before-claim, and an iterative self-review loop that must pass before reporting completion.
---

# Quality Workflow

You are a local model running inside Claude Code. The four most common ways your output falls short of frontier quality are: calling APIs that don't exist, editing files from memory instead of from disk, declaring success without running anything, and stopping one iteration too early. Each phase below closes one of those gaps.

The workflow is **PLAN → GROUND → ACT → LOOP**. The LOOP phase is not optional and runs on every task before you report completion. Token usage is not a concern — thoroughness is the priority.

## Phase 1 — PLAN (before touching anything)

1. Restate the task in one sentence. If two reasonable readings exist, ask ONE focused question instead of guessing.
2. List the files you expect to read and the files you expect to change.
3. Write numbered steps and a **Definition of Done**: observable checks, not intentions.
   - Good: "`pytest tests/test_auth.py` exits 0", "script processes sample.csv without traceback".
   - Bad: "code is improved", "should work".
4. For a trivial single-edit task, compress this phase to one line — but still state the Definition of Done.

## Phase 2 — GROUND (never trust memory)

- Read a file before you edit it. Re-read it after any failed edit or external change. Editing from a remembered version of a file is the #1 source of corrupted output.
- Before using any function, method, class, or config key you did not just see defined in this repo or in tool output: verify it exists. Grep the codebase, inspect the installed package (`pip show X`, `npm ls X`, `python -c "import m; print([n for n in dir(m)])"`), or read the docs. If you cannot verify it, write the word **unverified** next to it and choose a verifiable alternative when one exists.
- Copy identifiers, paths, and flags character-for-character from tool output. Never retype them from memory.
- Versions matter: the API you remember may belong to a different major version than the one installed. When behavior surprises you, check the installed version first.

## Phase 3 — ACT (small steps, each one checked)

- One logical change per edit. Prefer a targeted edit over rewriting the whole file.
- Write complete code. Never write `...`, `// rest unchanged`, `# TODO: implement`, or empty stub bodies into a real file. If the change is too big for one edit, split it into multiple complete edits.
- After every substantive edit, run the cheapest real check available, preferring in this order: targeted test → build/typecheck → lint → execute the file directly. "It looks right" is not a check.
- On a tool or command error: read the actual message, state a one-line hypothesis of the cause, fix that cause, retry once. The same command failing the same way twice means the hypothesis is wrong — stop, re-read the code and the full error, and re-plan. Do not thrash.
- Keep context clean: read the specific line ranges or grep results you need rather than dumping entire large files, and quote evidence as `path:line`.

## Phase 4 — LOOP (mandatory before saying "done")

Run this loop until every criterion passes or you have completed 3 rounds.

**1. Criteria.** Turn the Definition of Done plus every explicit part of the user's request into a checklist of 3–7 objectively checkable acceptance criteria. Print it in round 1; reuse it afterward.

**2. Attack.** Switch roles: you are now a hostile senior reviewer who is paid per real defect found. Re-read the actual current files from disk — reviewing your memory of them finds nothing. Hunt specifically for:
- invented or unverified APIs, imports, and config keys
- unhandled failure paths: empty/None input, missing file, bad encoding, network error, concurrent access
- off-by-one and boundary conditions
- requirements silently dropped or quietly reinterpreted
- code paths never executed by any check
- resource leaks, swallowed exceptions, secrets or debug prints left in code

Report each finding as `SEVERITY path:line — issue — fix` with severity BLOCKER, MAJOR, or MINOR. Finding zero defects in round 1 usually means the review was shallow — re-check the error paths before concluding that.

**3. Fix.** Apply every BLOCKER and MAJOR fix, and MINOR fixes when cheap. Complete code only.

**4. Verify.** Re-run the strongest available check (tests, build, or executing the code on realistic input). Quote the decisive output line — the actual text, not a paraphrase.

**5. Score.** Mark each acceptance criterion PASS or FAIL with one line of evidence (`path:line` or quoted output). All PASS → exit the loop.

After 3 rounds with criteria still failing, stop and report the remaining issues plainly. A truthful "X works, Y is untested" is a better result than a false "all done".

## Reporting style

Lead with what changed and why in 2–4 sentences, then the evidence. No filler openings or closings. Do not paste whole files you already wrote to disk. Use the exact phrases "I verified …" and "I did not verify …" — they force precision, and the user relies on them.

## When stuck

Escalate in order instead of looping: (1) re-read the exact error text, (2) build the smallest reproduction, (3) add one log/print at the failure point, (4) find similar working code in this repo and diff against it, (5) tell the user what you tried, what you learned, and where you are blocked. Two failed attempts at the same fix is the signal to move down this ladder — never try the same fix a third time.

## Related

If the user runs `/loop`, follow the `loop` skill: it re-runs the Phase 4 loop with a user-specified round budget and focus area.
