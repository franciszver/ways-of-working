# Observations — dated evidence for §7 working norms

Dated incidents that justify a working norm in `SKILL.md`. Kept here, out of the
body, so the skill stays short while the evidence stays available.

## 2026-07-24 — CI watch, pre-registration read as a verdict

An agent read "no checks reported" immediately after opening a PR as proof no
checks would run, and stopped. The checks were still registering — an unbounded
watch would instead have slept through a queued-runner stall. This is why the
rule requires polling until checks *exist* (a short loop, ~2-minute cap) before
reading their absence as a result, and why CI watches get a ceiling derived from
the pipeline's known runtime rather than an open-ended wait: a run still queued
never started (cancel and re-run it once), a run genuinely executing gets one
extension with a stated reason, and two strikes surface to the owner instead of
looping further.

## 2026-07-21 — subagent stopped to await a notification twice in one task

A subagent ended its turn to "wait" for a background, detached, or slow process
twice in the same task. Detached work produces no wake-up notification, so an
agent that stops to wait for one sleeps forever. The fix is a bounded foreground
loop (check → sleep → re-check) that continues in the same turn, with
long-running work launched foreground or harness-tracked, never
detached-and-then-stopped.
