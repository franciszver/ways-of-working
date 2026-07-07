---
name: declutter
description: Cleanup-only pass that applies behavior-preserving simplifications to a diff — fold duplication into existing helpers, delete dead code, collapse needless indirection. Not a bug hunt. Use before opening a PR or when asked to simplify/clean up recent changes.
---

# Declutter Protocol

You are a local model sweeping a diff for clutter. Token usage is not a concern — read every file the diff touches plus its neighbors. This pass APPLIES fixes (unlike deep-review) but has no design goal (unlike refactor): only subtraction. Behavior must be preserved, proven by tests.

## Step 0 — THE NET

Run the tests and record the result. Red suite → STOP (fix via debug first). No tests covering the diff → say so and do only the zero-risk subtractions (dead code, unused imports, debug leftovers); skip anything restructuring logic.

## Step 1 — SCOPE

Default: the branch's commits ahead of upstream plus uncommitted changes. Do NOT clean code the diff didn't touch — note pre-existing clutter for a separate pass. An explicit argument overrides.

## Step 2 — SWEEP, in value order

1. Duplication of what already exists — SEARCH the codebase before believing new code is new; folding into an existing helper is the highest-value move
2. Dead weight — unreachable branches, unused vars/params/imports, commented-out code, debug prints, done TODOs, fully-rolled-out flags
3. Speculative abstraction — interfaces with one implementation, config that never varies, layers that only forward (YAGNI)
4. Needless indirection — wrappers adding nothing, assign-once-use-once variables (unless naming a cryptic expression), classes that should be functions
5. Simpler equivalents — nested conditionals → guard clauses; hand-rolled loops → stdlib idiom; boolean gymnastics → the expression itself
6. Free inefficiency fixes — lookup hoisted from loop, list-membership → set. ONLY when also cleaner; anything needing measurement is the perf skill's job

## Step 3 — APPLY, IN YOUR LANE

- Apply each simplification; run affected tests as you go; full suite at the end.
- Found a BUG? DO NOT fix it here. Report it in deep-review format in the summary. Behavior changes hidden in cleanup diffs are the most dangerous kind.
- Module needs redesign? Out of scope — say so, point at refactor.
- Do not touch: public API surface (removing an unused public export is breaking — flag it), commented workarounds, performance-shaped code. Unsure if load-bearing → check callers and git history; still unsure → leave it, note it.

## Step 4 — PROVE AND REPORT

Full suite after must equal the before result — quote both. Report: removals grouped by category · net line delta · bugs noticed but NOT fixed · items deliberately left. Nothing found → state what you checked.

## Hard rules

- Never change behavior "while you're here" — the cardinal sin.
- Fewer characters is not simpler. Optimize for the next reader.
- Never restyle against the file's existing idiom.
- Never trust "obviously equivalent" without the test run — that's where behavior changes hide.
