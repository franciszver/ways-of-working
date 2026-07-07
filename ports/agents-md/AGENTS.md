# Agent operating rules

<!-- Drop this file at the repo root as AGENTS.md. It is the tool-agnostic
     distillation of the fable-quality-library: the quality floor plus compact
     protocols for the four highest-stakes moments (debugging, testing, review,
     claiming done). Add your project's commands in the marked section. -->

## Project commands

<!-- Fill in — verbatim, copy-paste runnable: -->
- Build: `<command>` · Test: `<command>` · Lint: `<command>` · Run: `<command>`

## Always

- **Verification gates "done".** Never report a task complete without running the real thing after your final edit and quoting the decisive output line. Check every requirement of the request against actual output, not memory of writing the code. Say exactly "I verified X (evidence)" / "I did not verify Y (reason)" — never imply an unchecked claim passed.
- **Ground every edit.** Read a file before editing it; re-read after any failed edit. Never use a function, import, flag, or config key you haven't confirmed in this repo, the installed packages, or tool output — label anything unconfirmable "unverified". Copy identifiers character-for-character from tool output.
- **Complete code only.** Never write `...`, `// rest unchanged`, or TODO stubs into a real file. Match the surrounding code's style. After each substantive edit, run the cheapest real check: targeted test → build/typecheck → lint → execute.
- **Stay in scope.** Do what was asked; log tempting side-improvements and report them at the end instead of doing them. Don't gold-plate; don't stop at "superficially works" when production quality was implied.
- **Report honestly, outcome first.** Failures reported with their output, unsoftened. No filler, no narration of the journey. Stuck after three refuted hypotheses → say so with the current state; a truthful "stuck" beats a confident guess.

## When something fails (debugging)

1. Reproduce first — exact command, exact output, re-runnable on demand. No edits before a repro exists. Can't reproduce → gather evidence (logs, env diff vs. a working instance); don't guess-fix.
2. Read the whole error; the FIRST error, not the last. Then state the gap: "expected A because <contract>; observed B."
3. Localize mechanically: stack trace → recent changes (`git diff`) → binary-search the data flow with one probe → differential vs. the closest working analog.
4. One hypothesis, one change, one observation per round; revert refuted changes immediately. The same fix failing twice means the hypothesis is wrong — never a third try. Three refuted hypotheses → re-read without a theory, shrink the repro, question one "known-good" assumption.
5. Fix the cause — state the chain root cause → mechanism → symptom first. Never widen a catch, delete a failing assert, or `sleep()` a race.
6. Prove: the original repro passes (quoted), a regression test fails without the fix, neighboring tests still pass, the final diff contains only the fix.

## When writing tests

Derive cases from the contract, not the code: normal, boundary (empty/single/many/huge; zero/negative/max; at-limit and one-past), and violation cases (invalid input → the promised failure behavior). One behavior per test; the name states the rule; assert observable behavior, not internals. Deterministic (inject clocks, seed randomness, fake the network at the boundary). Prove each load-bearing test can fail by breaking the code once. Never compute the expected value with the implementation's own logic; never `sleep()` for asynchrony.

## When reviewing code

Default scope: the branch's commits ahead of upstream plus uncommitted changes (a named target overrides). Diff first, then enough callers/callees to judge in context; a repo `REVIEW.md`'s severity rules override these defaults. State the change's intent in one sentence and check it against the code — requirement mismatch is the top defect class. Hunt: unhandled failure paths at every external boundary; state/races/idempotency; off-by-one and boundary values; injection and authz on every path; leaks on error paths; callers not updated; tests that would pass with the fix reverted. **Report only findings you verified** — concrete trigger scenario or discard; label each CONFIRMED (traced) or PLAUSIBLE (say what would confirm it). Format: `SEVERITY [CONFIRMED|PLAUSIBLE] path:line — defect — trigger — fix`, most severe first; verified bugs the diff didn't introduce get "(PRE-EXISTING)" and go last. A clean report states what was checked; a bare LGTM is not a review.

## Before claiming done

List every claim (explicit requirements + the silent ones: builds, existing behavior unchanged, the new error path fires). Strongest proof per claim: run the real flow > targeted test > typecheck/lint (never sufficient alone) > labeled static reasoning. Try the 3 most likely edge-breakers. Run pre-existing tests, not just new ones. Diff shows only intended changes. Then the verdict in the exact "I verified / I did not verify" form.

## Session continuity

If `HANDOFF.md` exists at the repo root: read it first, verify its two cheapest claims, execute its Next action, keep its ledger current. When ending a session mid-task: write it — goal (one line), numbered requirements with status + evidence, exact next action, decisions with reasons, gotchas, verbatim commands. Write for a reader with zero context from this session.
