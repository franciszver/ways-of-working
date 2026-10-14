---
name: clean-code
description: Guides writing and reviewing code for readability and maintainability, using clean-code heuristics inspired by Robert C. Martin. Covers names, functions, comments, formatting, data and object boundaries, error handling, tests, system construction, and code smells. These are heuristics, not fixed rules. Use when writing new code, reviewing a diff for readability, or judging whether code is easy to change. For a behavior-preserving restructure use refactor. For deleting dead code and clutter use declutter.
---

<!-- local: derived-from: skills/clean-code/SKILL.md@4cc37ada5d22 -->

# Clean Code Protocol

You are a local model writing or reviewing code for readability. These are heuristics, not rules. No fixed function length, no fixed argument limit, no required pattern. If a heuristic makes the code harder to read, drop it.

## Step 1 — NAMES

- Names reveal intent and are searchable. Use a named constant, not a magic number.
- One word per concept (not `fetch`, `get`, and `retrieve` together).
- Name length follows scope size.

## Step 2 — FUNCTIONS

- One thing at one level of abstraction.
- Guard clauses cut nesting. Plain beats clever.
- Side effects are visible in the name or moved out.
- Command or query, not both.
- Few arguments. No boolean flag that switches behavior; write two functions.
- Remove duplication only when the copies must change together.

## Step 3 — COMMENTS

- Code says what. Comments say why: intent, constraint, tradeoff, warning.
- No comment that restates code. Try a better name first.
- Delete commented-out code.

## Step 4 — FORMAT

- Follow the file's local style. Keep related code close. Let a formatter decide.

## Step 5 — DATA AND BOUNDARIES

- Hide representation. Do not reach through object chains.
- Plain transfer records at the edge. Validate at the boundary.
- Wrap third-party code behind a small interface you own.

## Step 6 — ERRORS

- Fail loudly. Never swallow an error.
- Keep context: what, which input, why. Keep the original cause.
- No null or sentinel the caller cannot tell from real data.

## Step 7 — TESTS AND CONSTRUCTION

- Tests are fast, independent, and read as one behavior each.
- Pass dependencies in. Build the object graph in one place.
- One switch in one place is fine. Repeated switches call for polymorphism.
- Keep logging, retries, and auth out of core logic when a clean way exists.

## Step 8 — SMELLS

Harmful duplication, rigidity, fragile coupling, needless complexity, dead code, stale comments. A smell is a hint, not proof.

## Step 9 — HANDOFF

Do not mix cleanup with behavior change. Restructure: use refactor. Remove clutter: use declutter. Stay in scope.

## Hard rules

- Heuristics are not laws.
- No abstraction that hurts readability.
- No unrelated restyling.
- No behavior change inside a readability cleanup.
