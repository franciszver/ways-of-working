---
name: prove
description: Proves work actually works before calling it done — strongest available evidence per claim, edge-case hunt, regression check, verbatim output quotes, and honest "I verified / I did not verify" verdicts. Use before reporting any task complete, before commits and handoffs, after fixes, and whenever the user asks "does it work?".
---

<!-- local: derived-from: skills/prove/SKILL.md@b2e27cc5cba1 -->

# Prove Protocol

You are a local model inside Claude Code. "Should work" is not "works". You may not say "done", "fixed", "working", or "complete" unless every step below ran AFTER your final edit. Any edit invalidates all earlier proof. Token usage is not a concern.

## 1. List the claims

Write the checklist: every explicit requirement from the request, PLUS the silent claims: it builds; existing behavior unchanged; the new error path actually fires; the config parses. 3–7 items. Each gets its own check.

## 2. Choose the strongest proof available — per claim

In this order — use the strongest one that exists:
1. RUN the real flow end-to-end (actual command / app / endpoint, realistic input)
2. Targeted automated test
3. Build / typecheck / lint (proves absence of one error class ONLY — never sufficient alone for a behavior claim)
4. Static read-through (weakest — you MUST label it "not executed, reasoning only")

Using a weaker check when a stronger one was available is the failure this protocol exists to stop. "Tests pass" while the app was never launched is the classic version.

## 3. Execute and capture

Run each check yourself, after the final edit. For each: record the command and paste the decisive output line VERBATIM (test summary line, HTTP status, computed value, exit code). For visual work, look at the render/screenshot — a UI declared done unseen is unverified. Paraphrased success ("tests passed") without the quoted line does not count and will be treated as unverified.

## 4. Hunt the edges — one deliberate pass

Pick the 3 most likely breakers for THIS change and actually try them:
empty / zero / negative · huge input · unicode · missing file · denied permission · duplicate submission · dependency down · wrong type.
Fix or flag what breaks. Do not skip this because the happy path passed — the false claims live on the error paths.

## 5. Check for regressions

1. Run the relevant PRE-EXISTING tests, not only your new one. Quote the summary line.
2. Poke the nearest neighboring feature once — the fastest check that would catch collateral damage.
3. Diff your changes: intended edits only. Remove debug prints, disabled tests, stray files.

## 6. Non-executable deliverables

Documents, plans, configs, schemas still need proof: walk the checklist against the artifact itself, not your memory of writing it; do one adversarial re-read for anything asserted but unverified or invented; and validate what has a validator (`--dry-run`, `--check`, schema validation, `terraform plan`, JSON/YAML parsing) — a config that never parsed is a bug you shipped.

## 7. Deliver the verdict

Use exactly these phrases — the user relies on them:
```
I verified: <claim> — <command> → "<quoted decisive line>"
I did not verify: <claim> — <why> — <what it would take>
```
Every claim from Step 1 appears in one of the two lists. NO claim may be implied as passing without appearing under "I verified". A partial-but-honest verdict beats a confident blanket "all done" every time. If a check fails, do NOT soften it, hide it, or silently patch and move on: report it, fix it under the `debug` skill protocol, then re-run this protocol from Step 3 — the fix was an edit, so all earlier proof is void.

## Report

```
Claims: <checklist items + silent claims proven>
Evidence: <command + quoted decisive output line, per claim>
Edge cases: <tried, and what happened>
I verified: <X> / I did not verify: <Y, and why>
```

## Proof levels by stakes

- **Throwaway script** — run it once on real input. Done.
- **Standard change** — real-flow run + edge pass + relevant existing tests.
- **Production-critical** — all of the above, plus independent verification from a fresh context, plus the edge pass on the *error* paths. In Claude Code, delegate the fresh-context pass to the `verifier` subagent; otherwise re-run the checks yourself in a fresh session with no memory of writing the code.

## Rules

- Observe after the last change, every time — memory of having written the code is not evidence.
- A check that cannot fail proves nothing: if a new test never failed, revert the fix once (or mutate the code) to watch it fail, then restore.
- A UI declared done unseen is unverified — look at the render or screenshot before reporting UI work complete.
- Half of verifying anything is the error paths — the happy path alone tells you almost nothing.
- Don't gold-plate: verify the claims made, at the stakes given.
