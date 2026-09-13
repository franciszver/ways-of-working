---
name: refactor
description: Behavior-preserving refactoring protocol — establish a test net first, transform in small verified steps, never mix structure changes with behavior changes. Use when restructuring, extracting, renaming, moving, de-duplicating, or modernizing code, or when asked to "clean up" working code.
---

<!-- local: derived-from: skills/refactor/SKILL.md@c6ad9c09797f -->

# Refactor Protocol

You are a local model. The contract is absolute: observable behavior identical, structure better. A behavior change hidden inside a refactor is the most expensive diff there is.

## 1. Build the net first

Run existing tests over the target, record green (quote the summary). Thin/absent coverage → write characterization tests that pin CURRENT behavior, quirks and bugs included — a found bug gets pinned and logged, NOT fixed here. No practical way to test → shrink step size until each step is trivially inspectable and say so. Mark a rollback point before the first change.

## 2. Keep the compatibility ledger

List what must not change: public signatures, exports, serialized formats, DB schemas, CLI flags, URLs, matched error messages, timing/ordering others depend on. A public interface that must change is not a refactor — split it out and label it breaking.

## 3. Transform in small named steps

One transformation type at a time (rename, extract, inline, move, replace-conditional, dedupe) — if you can't name it, you're rewriting. Run the net after every step: green → proceed, red → revert and re-approach, never debug forward through a half-applied refactor. Prefer mechanical moves, then grep for stragglers (strings, docs, configs, reflection). "While I'm here" fixes go on a follow-up list, not into this diff.

## 4. Finish clean

Net green on the final state, quoted. Ledger walked — every item confirmed unchanged. Read the final diff hunk by hunk: every hunk is structural; anything needing "and this also fixes…" gets pulled into a separate change. Deliver the follow-up list (bugs found, tempting improvements) separately.

## Scope control

Land what is currently done-and-green when scope creeps; replan the remainder as its own task. A merged half is worth more than an unmerged whole. Also ask whether the refactor is worth doing — churn on code nobody will touch again returns nothing.

## Report

```
Net: <baseline suite result, quoted> -> <final suite result, quoted>
Transformations: <named steps applied>
Ledger: <compatibility items confirmed unchanged>
Follow-ups: <bugs noticed, tempting improvements, deferred refactors>
```

## Anti-patterns

Refactor + feature/bugfix in one change · refactoring without a net ("I'll be careful" is not a net) · big-bang rewrite when incremental steps existed · "improving" behavior mid-refactor · style-only churn that burns review attention for no structural gain.

When done, run `prove` if part of a larger task; run `deep-review` on the diff when it touched anything load-bearing.
