---
name: spec
description: Turns a request into a numbered requirements ledger with acceptance criteria, explicit non-goals, surfaced ambiguities, and the riskiest assumption marked. Use when requirements are fuzzy or contradictory, when scoping a feature, or when asked for a spec.
---

<!-- local: derived-from: skills/spec/SKILL.md@4f6cd64ed502 -->
<!-- local: deliberate divergence: canonical sections 2+3 ("Number and classify" / "Acceptance criterion per MUST") are merged into one step here, and 5+6 ("Mark the riskiest assumption" / "Keep the ledger alive") into another, to fit the 45-line compact-variant budget; both merged sections keep the canonical content, just under one heading instead of two. "Size discipline" folds into the merged step 4 for the same reason. -->

# Spec Protocol

You are a local model. Most failed tasks fail at the spec — a dropped requirement, a never-surfaced assumption, an invented constraint. Build the ledger everything else builds against.

## 1. Extract every requirement — three kinds

Explicit (reread line by line — requirement #4 of 6 is the one that gets dropped) · Implicit (what the request assumes, e.g. "add login" implies existing users still work) · Negative (what must NOT change: behavior, contracts, performance).

## 2. Number, classify, and add an acceptance criterion per MUST

```
MUST   1. <requirement> — criterion: <observable check a stranger could run>
SHOULD 2. <requirement — do if cheap, say if skipped>
WON'T  3. <explicitly out of scope — and why>
```
"Works correctly" is not a criterion; "`pytest tests/test_auth.py` exits 0" is. Write at least two WON'Ts — they fence gold-plating on one side, silent scope creep on the other. If you can't write the criterion, you don't understand the requirement yet.

## 3. Surface ambiguities — decide or ask

For each reading that would change the work: **default and flag** (pick the sensible reading, record it, proceed — cheap-to-reverse guesses), or **ask** (only when wrong is expensive to undo — data model, public API, anything users see; batch questions into one round).

## 4. Mark the riskiest assumption, keep the ledger alive

Which single assumption, if wrong, invalidates the most work? Mark it — probe it first during execution. Statuses update as work proceeds (`DONE — evidence`, `IN PROGRESS`, `BLOCKED — on what`); it travels in handoffs; the final walk-through against outputs is the core of `prove`. Scale ceremony down for small tasks — a three-line request gets a three-item inline ledger, not a `SPEC.md`.

## Report

```
Ledger: <MUST/SHOULD/WON'T, numbered>
Acceptance criteria: <one per MUST>
Ambiguities: <resolved — default+flag, or asked>
Riskiest assumption: <named, with the cheapest probe planned>
```

## Anti-patterns

Restating the request in fancier words · acceptance criteria only the author can evaluate ("clean", "robust") · asking what the codebase already answers · specifying the solution instead of the requirement.
