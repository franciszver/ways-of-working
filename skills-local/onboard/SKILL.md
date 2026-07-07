---
name: onboard
description: Build a verified model of an unfamiliar codebase fast — orient from artifacts, trace one real flow end-to-end, predict-then-check, write down the map. Use when picking up an unfamiliar repo, service, or module before changing it.
---

# Onboard Protocol

You are a local model learning an unfamiliar codebase. Token usage is not a concern — read everything relevant. The danger is not ignorance; it's the plausible-but-wrong model built from file names and vibes. Every belief about this codebase is a hypothesis until verified against code or runtime.

## Step 1 — FIX THE GOAL

"Understand the codebase" is unbounded. Write the real goal: fix this bug (→ one flow) · add a feature to X (→ X's contracts and neighbors) · own this service (→ architecture + operations). The goal sets depth and kills tangents.

## Step 2 — ORIENT (breadth-first, timeboxed)

In information-per-minute order:
1. README/docs/ADRs — read as CLAIMS to verify, not facts; docs rot silently.
2. Build/run/test entry points (Makefile, package.json scripts, CI config) — the honest description of what the project does. GET THE TESTS RUNNING NOW: it verifies your environment and gives the green baseline you need before touching anything.
3. Top two directory levels + dependency manifest — architecture intent + actual stack.
4. Git: `git log --oneline -30` for what's active; most-touched files (`git log --format= --name-only | sort | uniq -c | sort -rn | head -20`) are the load-bearing walls; recent PRs show the conventions.

Output: an architecture sketch, explicitly labeled UNVERIFIED.

## Step 3 — TRACE ONE REAL FLOW

Pick the most representative operation and follow it through every layer: entry → dispatch → logic → persistence/external → response. Read the actual code at each hop; add logging or a debugger where reading gets speculative (DI, dynamic dispatch, middleware). One verified vertical slice beats any breadth pass. Bug goal → the failing flow is the slice (switch to debug). Feature goal → trace the closest existing sibling; it's also your template.

## Step 4 — INTERROGATE THE MODEL

- Question ledger: every "why is this here?" gets written down, not chased. Batch survivors for a human or a research-codebase pass.
- Predict-then-check: before opening a file, say what you expect; before running, predict the output. Wrong prediction = fix the sketch, not shrug.
- Chesterton's fence: the weird thing is load-bearing until `git log -p` on it says otherwise. Week-one cleanup instincts are wrong.

## Step 5 — LEAVE A TRAIL

Write the map: verified sketch, the traced flow, goal-relevant seams, surprises ("tests need Z running"), open questions + answers. Put it where the repo keeps notes. First change: something small and fully checkable, shipped through the project's FULL process (branch, review, CI) — the process is part of the codebase.

## Hard rules

- Never trust names ("utils/ is trivial", "legacy/ is unused") over evidence.
- No redesign opinions before tracing a flow.
- Don't ask humans what artifacts answer; don't grind hours on what a maintainer answers in a sentence — batch questions with evidence attached.
- Never "read around" a broken build — fix the environment first; you can't onboard onto a system you can't observe.
