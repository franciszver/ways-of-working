---
name: testgen
description: Writes tests that hunt bugs, not coverage theater — cases derived from the contract and its boundaries, each test proven able to fail, assertions on observable behavior. Use when writing or improving tests, adding regression tests after a fix, or when asked to "add test coverage" for existing code.
---

<!-- local: derived-from: skills/testgen/SKILL.md@091e25ac7d5c -->

# Testgen Protocol

You are a local model. A test's value is the probability it fails when the code is wrong, not lines executed. Write each test as a trap set for a specific bug class.

## 1. Derive cases from the contract, not the code

From each promise the unit makes: **Normal** (representative input → promised output) · **Boundary** (empty/single/many/huge, zero/negative/max, exactly-at-limit) · **Violation** (invalid input → promised failure behavior). Deriving from the implementation instead ("line 12 has an if") reproduces the author's blind spots.

## 2. Sweep the standard boundary table

empty/single/many/huge · zero/negative/float-precision/integer-max · unicode, whitespace, injection-shaped strings (`'; DROP`, `../..`, `<script>`) · missing/malformed/duplicated · timezone, DST, leap day, epoch, clock skew · concurrent same-op-twice, interleaved writers · collaborator throws/times out/returns partial data.

## 3. Make each test a good instrument

One behavior per test, name states the rule (`rejects_expired_token`, not `test_2`). Assert observable behavior (return value, event, persisted state) — never internals. Deterministic: inject clock, seed randomness, fake network at the boundary. Independent: any subset runs in any order.

## 4. Prove the test can fail

Break the code deliberately (revert the fix, mutate the condition), watch the test fail for the stated reason, restore. A regression test that never failed on the pre-fix code is not a regression test.

## 5. Choose honest oracles

Exact expected values > property checks > snapshots. Properties for round-trips, idempotence (`f(f(x)) == f(x)`), invariants. Never compute the expected value with the same logic as the implementation.

## 6. Spend tests where bugs are expensive

Prioritize boundaries/error paths, money/time/auth/concurrency, anything that just had a bug, public contracts. Skip framework behavior, trivial getters, mock-talks-to-mock tests.

## Mock discipline

Mock at the system boundary (network, clock, filesystem) — never in the middle of your own logic. Every mock encodes an assumption; know where it's verified or flag that it isn't.

## Anti-patterns

"Runs without throwing" as sole assertion · one giant happy-path test · expected values copy-pasted from current output without checking correctness · `sleep()` for asynchrony · writing to satisfy a coverage number.

Proving a fix? Pair this with `prove` — the regression test is step one of its evidence.
