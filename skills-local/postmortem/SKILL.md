---
name: postmortem
description: Blameless postmortem — factual timeline, plural contributing causes, action items that would each have prevented or shortened the incident. Use after an incident, outage, data loss, or near-miss.
---

# Postmortem Protocol

You are a local model writing a postmortem. The incident's cost is sunk; the only variable is how much learning it buys. Test for the final document: would its action items, had they existed before, have prevented or materially shortened the incident?

## Step 1 — TIMELINE, FACTS ONLY

From the incident log, alerts, deploy history, chat: timestamped observable events — what happened, what people saw, what they did. NO causes, no "mistakenly", no "should have" yet. Include: impact start (often before detection — measure that gap), detection, mitigation, resolution. The gaps between those are findings: a 4-hour detection gap is usually a bigger lever than the bug.

## Step 2 — BLAMELESS AS METHOD

Write people as roles ("the on-call", "the deploying engineer"). They acted on the information and incentives the SYSTEM gave them; the next person gets the same ones, so fixing the person fixes nothing. Every time you land on "human error", ask what made the error easy: misleading dashboard, similarly-named configs, alert fatigue, missing runbook. "Human error" as a conclusion = analysis stopped early. "Be more careful" = not an action item.

## Step 3 — CAUSES, PLURAL

Incidents happen when several defenses fail together: the bug existed AND review missed it AND tests didn't cover it AND the canary didn't catch it AND the alert didn't fire. Walk each link with "and why didn't anything stop it there?" Each failed defense is a candidate fix — usually cheaper than eliminating the bug class. Separate TRIGGER (the deploy) from CONDITIONS (the latent bug, missing limit): removing only the trigger leaves the conditions armed. Also list what went WELL — defenses to keep funded.

## Step 4 — ACTION ITEMS THAT BIND

Each must be: specific (changes a system, not vigilance) · owned (a name) · dated · connected (which gap it closes: prevention, detection, mitigation speed, blast radius). Rank by leverage: bug-class fix > this-bug fix; detection fix that shortens ALL future incidents can beat both. Three funded items beat twelve aspirational. Schedule the follow-up check — expired action items teach the org postmortems are theater.

## Step 5 — DOCUMENT

Summary (3 sentences) · Impact (user terms, measured) · Timeline (gaps called out) · Causes (trigger, conditions, failed defenses) · What went well · Action items (owner, date, gap closed) · Appendix (logs, graphs). Quote exact error messages — write for the person searching for them in two years. Publish where the team reads; circulate the draft before any meeting.

## Hard rules

- No counterfactual pile-on ("X should have noticed") — analyze what the information available at the time supported.
- No "add more tests / improve monitoring" — which test, which class, which signal?
- Impact numbers are measurements, not narrative.
- Near-misses get postmortems too — same learning, zero damage.
