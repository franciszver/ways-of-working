---
name: incident
description: Production incident response — mitigate before diagnosing, smallest reversible action first, timestamped log, communicate on a cadence. Use when production is down or degraded, an alert fires, or users are impacted.
---

# Incident Protocol

You are a local model responding to a production incident. Rule zero inverts normal engineering: MITIGATE BEFORE DIAGNOSING. Root cause comes later (debug skill, after recovery); learning comes later (postmortem skill). Now: how bad, stop the bleeding, tell people.

## Step 1 — ASSESS (2 minutes)

- Impact: who's affected, what can't they do, since when? Check the user-facing symptom yourself.
- Severity: all vs some vs internal; data being CORRUPTED outranks requests failing (a down system writes no bad data).
- Trajectory: worsening, stable, or self-recovering?
State the assessment in the channel — it anchors everything after.

## Step 2 — LOG

Timestamped, append-only, from minute one: observations, actions, effects. Log every state-changing action BEFORE taking it. The log prevents conflicting changes and repeated failed attempts, and it becomes the postmortem's raw material.

## Step 3 — MITIGATE

Ask "what change returns service fastest at lowest risk", not "what's the bug":
- WHAT CHANGED? Deploys, config, flags, provider incidents. Rollback of the suspect change is the DEFAULT first move — correlation is enough to un-deploy; you don't need proven causation.
- No candidate change → shed and shield: flag off the failing feature, fail over, scale up, rate-limit, serve degraded (cached/read-only).
- Reversible beats clever. Touching data → snapshot first.
- ONE mitigation at a time, verified against the user-facing symptom before the next. A mitigation that worsens things → revert immediately.

## Step 4 — COMMUNICATE

Impact in user terms, current status, next update time — then KEEP THE CADENCE even with nothing new ("still investigating, next update 15:30"). No cause speculation externally, no guessed ETAs. Multiple responders → name the coordinator (communicates) vs hands-on-keyboard (investigates).

## Step 5 — STAND DOWN

Recovered = user-facing symptom gone through one full cycle (traffic peak, cron run). Then: declare the end · file follow-up tickets NOW (disabled flag, skipped root cause, snapshot cleanup) · preserve evidence before it rotates (logs, metrics, dumps) · schedule the postmortem · THEN root-cause via debug.

## Hard rules

- Mitigation is not the fix. The incident ends twice: once for users, once when the root cause is fixed and the mitigation unwound.
- Irreversible actions (data deletion, one-way failover, restarting the only stateful replica) get a second person's ack even mid-incident.
- Blame is operationally useless and hides information. "The deploy correlates" is a fact; whose deploy is irrelevant.
- Two failed mitigation attempts and you're guessing → escalate. Fresh eyes beat heroics.
