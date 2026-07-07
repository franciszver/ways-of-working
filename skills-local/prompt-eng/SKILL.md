---
name: prompt-eng
description: Prompts engineered like software — explicit contract with examples, tested against a case set, debugged by evidence. Use when writing or debugging prompts, system prompts, or LLM-powered features.
---

# Prompt Engineering Protocol

You are a local model engineering a prompt. A prompt is a program run by a stochastic interpreter — it gets a spec, tests, and evidence-driven debugging. Iterating on vibes (rewrite, eyeball one output, repeat) is forbidden.

## Step 1 — SPEC BEFORE PHRASING

Write down: the task in one sentence · exact output format with ONE literal perfect example · who consumes the output (parser? human? another prompt?) · 3–5 representative inputs INCLUDING the ugly ones (empty, adversarial, off-topic, too long) and correct handling of each.

## Step 2 — DRAFT WITH THE MECHANICS THAT MATTER

- Observable behaviors, not quality adjectives: "cite the section number per claim; no supporting section → say so" steers; "be thorough" doesn't. Say what TO do, not only what to avoid.
- 1–5 input→ideal-output examples spanning the space, including one edge case. Examples are load-bearing: the model imitates their INCIDENTAL patterns too (length, tone) — make examples exactly right, incidentals included. Examples must not contradict instructions (the model follows the examples).
- Delimit instructions vs context vs untrusted input unambiguously (XML tags / sections). One concatenated blob = injection bug AND correctness bug.
- Escape hatch for every "always do X": say what happens when X is impossible ("input not valid JSON → output {\"error\":...}"). Unspecified impossible-cases are where hallucination lives.
- Judgment tasks: reasoning BEFORE the verdict in the output order, or you get post-hoc rationalization.
- Cut rules that don't change behavior — every rule dilutes the others.

## Step 3 — TEST LIKE CODE

- Build the eval set: the Step 1 cases + real inputs as they arrive; 10–20 cases. Every production failure joins it permanently.
- Grade per case against stated criteria; subjective criteria get a written rubric ("≤3 sentences, no invented citations"), never "good".
- Run the FULL set on EVERY prompt change — the defining failure is whack-a-mole: the fix for case 7 breaks cases 2 and 9. One case checked = coin flip.
- A case passing 3-of-5 runs is a flake = a real clarity bug in the prompt, not noise.

## Step 4 — DEBUG BY EVIDENCE

Diagnose each failing case BEFORE editing; the categories have different fixes:
- MISSING INFO → add context
- AMBIGUOUS instruction (it took the other reading) → tighten wording
- CONFLICTING rules (it picked) → decide the priority yourself, encode it
- CAPABILITY CEILING (clear ask, can't do) → decompose, add worked examples, or upgrade the model — rewording won't cross a ceiling, and neither will ALL CAPS
- EXAMPLE DRIFT (imitating an incidental pattern) → fix the examples
One change per iteration, re-run the set, keep only net-positive. Can't say WHY a change helped → superstition; it will regress.

## Step 5 — SHIP AS AN ARTIFACT

Version prompts with the code using them; changelog behavior changes; re-run the eval set on every model swap (a model upgrade is a major-version dependency bump). In production: log inputs/outputs (the future eval set), monitor parse rate / refusal rate / length drift — prompt regressions arrive with traffic shifts, not deploys.

## Hard rules

- No kitchen-sink prompts of accumulated patches — declutter applies to prompts too.
- The happy path is not the spec; the empty/adversarial/off-topic cases are where LLM features fail.
- Any prompt processing untrusted text gets delimiter discipline + a test case where the input tries to override the instructions.
