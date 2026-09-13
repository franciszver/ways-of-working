---
name: lean-max-effort
description: Runs the four-phase backbone for non-trivial work — Capture (requirements
  ledger, riskiest assumption first), Plan, Execute lean, Verify before done. Use
  when a task spans multiple steps, files, or tool calls, or when the user asks for
  thoroughness, tokens, budget, or efficiency.
---

# Lean Max Effort

Frontier-quality runs differ from mediocre ones mostly in **process, not raw intelligence**: dropped requirements, unproven "done" claims, shotgun debugging, and wasted tokens (narration, re-reading, echoing) are all process failures. Fix both at once: **reallocate tokens from zero-value activity into high-leverage activity.**

Run every task through four phases: **Capture → Plan → Execute lean → Verify.**

## 1. Capture

Before touching a tool, extract every explicit and implicit requirement into a short numbered ledger — the single cheapest way to avoid delivering work that silently drops requirement #4 of 6. On long tasks, write it to a scratch file so it survives context pressure. Then name the **riskiest assumption** — the belief that, if wrong, invalidates the most work — and resolve it first with the cheapest probe available. Run `spec` for the full ledger method (MUST/SHOULD/WON'T, acceptance criteria, non-goals).

## 2. Plan

Decide the approach before executing — a wrong path costs 10–100x a brief plan. Name which files change, or what evidence would answer the question, before the first tool call. If two approaches look equal, choose the one that is cheaper to verify. Keep the plan proportional: two sentences for a two-step task. For hard-to-reverse decisions, run `architect`; for multi-step or multi-session work, run `breakdown`.

## 3. Execute: lean

Every token either moves the task forward or gets cut:

- **Read surgically** — line ranges, grep, outlines; never re-read an unchanged file.
- **Never echo** file contents or tool output the user already has.
- **Kill narration** — no "Now I will…", no play-by-play.
- **Batch work** — one verification run per coherent batch, not per edit.
- **Edit, don't regenerate** — targeted replacements, never a full rewrite for three lines.
- **Right-size the ending** — state the result and what was verified; no journey recap.

## 4. Verify: this is where "max effort" actually lives

Never declare done without running the code, the tests, or opening the generated file — "should work" is a guess. Walk the ledger against actual output, not memory. Spend one deliberate pass hunting what breaks the change. Run `prove` for the full evidence protocol (proof levels, edge-case sweep, regression check, verdict phrasing) and `debug` for any failure found along the way.

A failed check loops back to Execute — cap it at 3 iterations per failure; two iterations that don't reduce the failure count means you're oscillating, so stop and report honestly instead. Prose/design deliverables get exactly one structured revision pass, not a loop.

## Spend vs. cut — the allocation table

| Spend tokens on | Cut tokens from |
|---|---|
| Requirements ledger, riskiest assumption first | Narrating tool use, re-reading unchanged files |
| A brief plan before execution | Echoing file contents back |
| Running/verifying the actual output | Regenerating whole files for small edits |
| Edge-case hunt before finishing | Recaps, preambles, closing essays |
| Loop iterations gated by a failing objective check | Loop iterations gated by "let me polish this more" |

## Anti-patterns

- Starting to edit before understanding what the task requires.
- "Done!" without having run or opened the thing.
- Re-reading a 500-line file for the third time because nothing was noted down.
- Stopping at the first version that superficially works when production quality was implied — or its mirror, gold-plating past what was asked.
- Answering at length a question the user did not ask while under-answering the one they did.
- Open-ended self-revision loops with no objective signal.

When the task is genuinely beyond available capability, say so and recommend escalation — honest escalation is cheaper than a confident wrong answer.
