---
name: prove
description: Proves work actually works before calling it done — strongest available evidence per claim, edge-case hunt, regression check, verbatim output quotes, and honest "I verified / I did not verify" verdicts. Use before reporting any task complete, before commits and handoffs, after fixes, and whenever the user asks "does it work?".
---

# Prove Protocol

You are a local model inside Claude Code. "Should work" is not "works". You may not say "done", "fixed", "working", or "complete" unless every step below ran AFTER your final edit. Any edit invalidates all earlier proof. Token usage is not a concern.

## Step 1 — LIST THE CLAIMS

Write the checklist: every explicit requirement from the request, PLUS the silent claims: it builds; existing behavior unchanged; the new error path actually fires; the config parses. 3–7 items. Each gets its own check.

## Step 2 — PICK THE STRONGEST CHECK PER CLAIM

In this order — use the strongest one that exists:
1. RUN the real flow end-to-end (actual command / app / endpoint, realistic input)
2. Targeted automated test
3. Build / typecheck / lint (proves absence of one error class ONLY — never sufficient alone for a behavior claim)
4. Static read-through (weakest — you MUST label it "not executed, reasoning only")

Using a weaker check when a stronger one was available is the failure this protocol exists to stop. "Tests pass" while the app was never launched is the classic version.

## Step 3 — EXECUTE AND QUOTE

Run each check yourself, after the final edit. For each: record the command and paste the decisive output line VERBATIM (test summary line, HTTP status, computed value, exit code). Paraphrased success ("tests passed") without the quoted line does not count and will be treated as unverified.

## Step 4 — EDGE HUNT

Pick the 3 most likely breakers for THIS change and actually try them:
empty / zero / negative · huge input · unicode · missing file · denied permission · duplicate submission · dependency down · wrong type.
Fix or flag what breaks. Do not skip this because the happy path passed — the false claims live on the error paths.

## Step 5 — REGRESSION CHECK

1. Run the relevant PRE-EXISTING tests, not only your new one. Quote the summary line.
2. Poke the nearest neighboring feature once — the fastest check that would catch collateral damage.
3. Diff your changes: intended edits only. Remove debug prints, disabled tests, stray files.

## Step 6 — VERDICT

Use exactly these phrases — the user relies on them:
```
I verified: <claim> — <command> → "<quoted decisive line>"
I did not verify: <claim> — <why> — <what it would take>
```
Every claim from Step 1 appears in one of the two lists. NO claim may be implied as passing without appearing under "I verified". A partial-but-honest verdict beats a confident blanket "all done" every time.

## When a check fails

Do NOT soften it, hide it, or silently patch and move on. Report it, fix it under the `debug` skill protocol, then re-run this protocol from Step 3 — the fix was an edit, so all earlier proof is void.
