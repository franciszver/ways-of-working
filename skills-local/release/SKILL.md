---
name: release
description: Ship so failure is cheap — verify the exact artifact, stage the exposure, watch signals against baseline, keep rollback instant. Use when deploying, releasing, publishing, or flipping a major feature flag.
---

# Release Protocol

You are a local model running a release. A release is a bet; make it cheap to lose: small increments, watched closely, reversible instantly.

## Step 1 — BEFORE

- Read the exact diff since the last released version as a list of RISKS. Migrations, auth, config parsing, serialization → extra care.
- Everything green on the exact artifact shipping (same commit, same build).
- Write the rollback answer: the command, how long it takes, and — critical — does this change BREAK rollback? (Schema migrations, one-way transforms, protocol bumps can make the old version unable to run → use expand-migrate-contract from the migrate skill.)
- Timing: responders around and watching. Not Friday evening, not the traffic peak, not alongside another launch.

## Step 2 — STAGE THE EXPOSURE

Never 0→100. Ladder: dev → staging → canary (few % / one instance) → ramp → full.
- Define BEFORE shipping what promotes each rung: which signal, watched how long ("error rate and p95 flat vs baseline on canary for 30 min"). A canary nobody compares to baseline is just a slow deploy.
- Feature flags decouple deploy from release: ship dark, flip separately. Flag-off is the fastest rollback that exists. Ticket the flag's removal when fully ramped.

## Step 3 — AFTER

Deploy exit 0 is when the experiment STARTS.
- Watch user-facing signals (errors, latency, key metric) against pre-release baseline + the changed component's logs. New-in-this-release error strings are the highest-signal alert.
- Watch the delayed shapes: memory creep, first cron/batch run, cache expiry, first traffic peak — define how long "watched" lasts accordingly.
- Exercise the shipped feature once, end-to-end, in prod. Silent no-op "successes" are common.

## Step 4 — WHEN IT GOES WRONG

Roll back first, diagnose second (incident skill owns the protocol). Roll FORWARD only if the fix is minutes away and understood — pressure hotfixes have the highest defect rate of any code. A rolled-back release re-ships from the TOP of the ladder.

## Step 5 — THE CHECKLIST

The release checklist lives in the repo, versioned; follow it by READING it, not from memory; every incident adds its lesson to it. Tag what shipped; changelog for the operator diffing versions mid-incident (behavior changes, new config, what to watch).

## Hard rules

- Batching a week of merges because releases hurt is backwards — pain means release SMALLER and MORE OFTEN.
- "Quick config change" goes through the same ladder — config causes incidents at code's rate.
- Never promote a canary on "no pages yet after five minutes".
- Never declare victory at deploy-success; the bug arrives with the first peak.
