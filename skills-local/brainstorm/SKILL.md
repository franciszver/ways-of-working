---
name: brainstorm
description: Structured ideation — generate wide without judging, force variation with named moves, converge with explicit criteria and kill reasons. Use when asked to brainstorm, generate options or names, or find alternatives to a stuck approach.
---

<!-- local: derived-from: skills/brainstorm/SKILL.md@3d2f3c1f3eac -->

# Brainstorm Protocol

You are a local model running a brainstorm. The failure mode is one idea five times: the first plausible idea becomes the template for everything after. The cure is mechanical: generate and judge in SEPARATE phases, and force variation with the moves below. Deliverable = a decision-ready shortlist, not confetti.

## Step 1 — FRAME

State the need one level above the requested artifact ("names for the caching library" sits under "make it adoptable and memorable"). List hard constraints (budget, compatibility, law); explicitly SUSPEND soft ones ("we've always done X") for the session. If a favored solution exists, write it down and set it aside visibly — otherwise it silently becomes the benchmark.

## Step 2 — GENERATE (no judging allowed)

Minimum 15 ideas, numbered, one line each — target 20–30. The first five are everyone's ideas; originality lives past the comfort point. No evaluation, no feasibility talk, no "but". When stalled, switch angles — do not push the same one:
- INVERT: how would we guarantee failure? (reverse each answer) What if we did nothing?
- EXTREMES: 10x budget · $0 · ship tomorrow · 1 user · 1M users
- PERSPECTIVES: how would a security engineer solve it? a game designer? nature? a market?
- DECOMPOSE & RECOMBINE: split the problem, generate per part, cross-breed
- ANALOGY: who has the structurally identical problem in another domain?
- REMOVE THE SACRED PART: design without the component everyone assumes is fixed

Long descriptions in this phase are evaluation in disguise — keep lines terse.

## Step 3 — CONVERGE (judging, but explicit)

1. Cluster into families; a one-member cluster is often the interesting one.
2. State criteria BEFORE scoring (impact, cost, reversibility, fit) — criteria chosen after seeing favorites is rigged.
3. Shortlist 2–4 genuinely DIFFERENT candidates — best of each strong family, never the top four of one family.
4. Kill with reasons: one line per notable discard. "Killed by soft constraint" entries get flagged for revisit.
5. Salvage before discarding: the strongest ideas are often hybrids ("A's mechanism with B's interface").

## Step 4 — HAND OFF

Output: shortlist with a one-line case each · the criteria used · the kill list · the cheapest test per candidate (the spike/prototype that would falsify it). Real stakes → feed the architect skill. A brainstorm never silently becomes a commitment — picking the winner is a separate explicit act.

## Hard rules

- One "that won't work because…" during generation reshapes everything after it. Zero evaluation until Step 3.
- Strong-opinion inputs (the boss's idea) go in LAST.
- Fifteen paraphrases ≠ fifteen ideas — mechanisms must differ, not words.
- Timebox both phases; refusing to converge is as sterile as refusing to diverge.
- Keep the discards — the kill list is half the value.
