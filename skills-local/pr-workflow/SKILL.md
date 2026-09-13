---
name: pr-workflow
description: Branch-to-merge hygiene — one concern per PR, commits that tell the story, description that fronts why and risk, disciplined review response. Use when creating commits/PRs, preparing work for review, or responding to review.
---

<!-- local: derived-from: skills/pr-workflow/SKILL.md@aab4a6495dc1 -->

# PR Workflow Protocol

You are a local model preparing work for review. A PR is an argument that a change is safe to merge, made to a reader with limited time. Optimize one variable: how cheaply the reviewer can reconstruct and check your reasoning. Past ~400 lines of judgment code, defect-finding collapses and LGTM measures fatigue.

## Step 1 — ONE CONCERN PER PR

One deliberate change: a feature, a fix, a refactor — never "the feature, plus a drive-by rename, plus reformatting". Standard splits (also the merge order):
- Refactor-then-behave: enabling refactor as its own no-behavior-change PR (tests pass unchanged), then the small behavior change.
- Mechanical-then-manual: the codemod/rename/format 400 lines separately from the 30 judgment lines.
- Expand-then-contract for migrations (migrate skill).
If the summary needs "also", it's two PRs. Label generated files/lockfiles so the reviewer knows what not to read.

## Step 2 — COMMITS ARE THE NARRATIVE

Present history as a reasoned sequence: each commit one buildable logical step (bisect will land on it). Message subject = the change, imperative mood. Body = WHY: the constraint, the bug link, the rejected alternative. "update handler.py" stores zero information. Squash the wip/fix-typo noise before review.

## Step 3 — THE DESCRIPTION

Front-load, in order:
1. WHAT & WHY — the problem in 1–2 sentences before the solution; link the issue.
2. HOW — the approach + the alternative you rejected (pre-empts "why didn't you just").
3. RISK & PROOF — what could break + the evidence it doesn't: tests added, verification run, output QUOTED. This is the highest-value, most-skipped section.
4. Guided tour if the diff is nonlinear ("start at router.py; the rest is plumbing").
Then self-review: read your own full diff AS the reviewer (deep-review self-pass), remove debug prints and stray files, run the suite. Every defect the reviewer catches that you could have is goodwill spent badly.

## Step 4 — REVIEW DIALOGUE

Every comment gets a response: FIXED (with the commit) · PUSHBACK (with reasoning — disagreement is legitimate, silence is not) · DEFERRED (with a ticket link, only for separable work). Push response commits WITHOUT force-push during review so the reviewer can diff-since-last-look. Reviewing others: approach first, mechanics second; mark blocking vs preference explicitly; turnaround is production work — a PR waiting two days costs more than most bugs.

## Step 5 — MERGE

Green CI, resolved threads, up to date with base. Squash-merge → the PR title/description become the commit: write them like it. Delete the branch. Merged-but-undeployed is inventory; it rots.

## Hard rules

- Never force-push over an in-progress review.
- Never mix review-response commits with new feature work.
- "Will fix in a follow-up" requires the ticket link, in the same comment.
- No self-merging "trivial" changes without review — the exception buys nothing and normalizes the bypass.
