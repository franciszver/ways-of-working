---
name: estimate
description: Calibrated estimates — decompose, size against comparable past work, attack unknowns with spikes, deliver a range with assumptions. Use when asked how long, how big, or how much effort something is.
---

<!-- local: derived-from: skills/estimate/SKILL.md@7fe2a2e5b32b -->

# Estimate Protocol

You are a local model producing an estimate. An estimate is a probability distribution; the honest product is a RANGE plus the assumptions that would break it. Your gut number is the optimistic bound, not the middle.

## Step 1 — ESTIMATE THE RIGHT THING

Pin what "done" means before sizing — "add export" is 2 days for CSV-happy-path, 3 weeks for all-formats-with-permissions. Fuzzy scope → give per-interpretation numbers ("CSV only: X; full: Y"); the gap forces the scope decision now. Include the whole cost: review, tests, docs, deploy, migration, coordination — code is routinely the minority.

## Step 2 — DECOMPOSE AND MARK

Break into parts small enough that each resembles something actually done before; size by reference ("the last three similar endpoints took ~2 days each"), never by intuition about a novel whole. Mark each part:
- KNOWN — done it before
- VARIABLE — done similar, details differ
- UNKNOWN — never done / depends on something unexamined
The unknowns are where the estimate dies.

## Step 3 — ATTACK UNKNOWNS

An unknown sized by guessing gets a wide guess; a timeboxed SPIKE (read the API docs, prototype the join, measure the volume) often collapses it to a known for an hour's cost. Still unknown → estimate the DISCOVERY: "2 days to determine feasibility, then re-estimate". Never emit a number-shaped shrug. "Can't usefully estimate until after the spike" is a legitimate answer.

## Step 4 — CORRECT FOR BIAS

- Planning fallacy is the default: best-case parts compose into an impossible whole. Treat the gut total as the range's bottom.
- Check your actuals: what did the last few "2-day" tasks really take? Apply that ratio.
- Integration and iteration are line items — parts that each work take real time to work together, and v1 will be revised. Missing both = fantasy decomposition.
- A deadline is not an estimate. Fixed date → convert honestly to scope: "by the 15th: X and Y, not Z".

## Step 5 — DELIVER

```
Likely N–M <units> · assumes: <2–4 assumptions that break the number>
· biggest risk: <the unknown + the spike that shrinks it>
· cut line: <what drops to hit the low end>
```
Width is information. Forced to one number → attach confidence ("70% by the 20th"). When new information moves the estimate, say so THE MOMENT it moves — a re-estimate at 30% done is a correction; at 95% it's a betrayal.

## Hard rules

- Never anchor on the number in the question ("quick, right?") — decompose first.
- Never estimate under social pressure in the moment; "range in an hour" is professional.
- No silent padding — it destroys calibration and gets negotiated away anyway.
- No precision theater: "13.5 hours" with ±3-day unknowns. Digits must match knowledge.
- Compare estimates to actuals afterward — that loop is where calibration comes from.
