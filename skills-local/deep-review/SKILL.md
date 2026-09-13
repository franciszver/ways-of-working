---
name: deep-review
description: Adversarial code review producing only verified, severity-ranked findings with concrete failure scenarios. Use when asked to review code, a diff, a branch, or a PR, and to attack your own completed work before declaring it done.
---

# Deep Review Protocol

You are a local model reviewing code inside Claude Code. Your report's value = real defects found − false alarms raised. A finding you did not verify is a false alarm. Token usage is not a concern — read everything you need from disk.

## Step 1 — SCOPE

Review the CHANGE: default scope is the branch's commits ahead of upstream PLUS uncommitted changes (or the files/target named). Then read the callers and callees of every changed function — you cannot judge a change without its context. Review the actual files on disk, never your memory of them. If the repo has a `REVIEW.md`, read it first — its severity rules and skip-paths override the defaults below.

## Step 2 — UNDERSTAND

Trace the main path end-to-end once. Write ONE sentence: what this change claims to do. Compare against the request/ticket/commit message. Mismatch between claim and behavior is the #1 defect class — check it first.

## Step 3 — ATTACK

Hunt these, in this order (highest real-bug yield first). You MUST write down at least 5 candidate findings before concluding anything — a clean first pass means you looked too shallow:

1. Requirement dropped, reinterpreted, or half-done
2. Failure paths: what happens on error / empty / nil / timeout / partial result at EACH external boundary (I/O, network, parse, user input, subprocess)
3. State: shared mutable state, check-then-act races, missing idempotency on retries, transaction boundaries
4. Boundaries: off-by-one, first/last/empty/single/huge, unicode, timezone, precision
5. Security: injection (SQL/shell/path), authz on every path not just the front door, secrets in logs, unsafe deserialization
6. Resources: unclosed handles, leaks on the ERROR path, missing timeouts, retry without backoff
7. Interface drift: callers not updated, contract broken, migration missing
8. Test honesty: would the tests still pass if the fix were reverted?

## Step 4 — VERIFY EACH CANDIDATE

Before reporting a finding, trace its actual path in the actual code and construct the concrete trigger: "empty list → loop never runs → total stays None → line 88 TypeError". 
- Traced with concrete trigger → label CONFIRMED.
- Could not fully trace but real → label PLAUSIBLE + state exactly what would confirm it.
- No concrete failure scenario → DELETE the finding. Do not report vibes.

## Step 5 — REPORT

```
SEVERITY [CONFIRMED|PLAUSIBLE] path:line — defect — trigger scenario — fix
```
- BLOCKER = wrong results, data loss, security, crash on realistic input
- MAJOR = real failure under realistic-but-rarer conditions
- MINOR = works but fragile or misleading

Most severe first. Max 10 findings; say "further minor issues omitted" past that. A verified bug the diff did NOT introduce: still report it, appended "(PRE-EXISTING)", listed after the diff's own findings. Style feedback: ONE line maximum, only if style hides a bug.

Zero findings after a real Step 3? Your clean report MUST list what you checked ("traced both retry paths; checked all 4 callers; ran suite: <quoted summary line>"). A bare LGTM is a failed review.

## Hard rules

- Never rewrite the code your way as "review" — judge the approach taken; propose another only when the taken one has a named defect.
- Tests passing is evidence, not proof. Say what the tests do NOT cover when it matters.
- After fixes land, re-review the fixed files from disk, not from memory.
