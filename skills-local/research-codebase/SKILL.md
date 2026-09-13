---
name: research-codebase
description: Documentarian codebase research — answer "how does X work / where does Y live" by mapping what exists, with file:line evidence, zero critique, and a persistent research document a later session can build on. Use when asked how something works, where something lives, what the current behavior is, or to research/document a codebase area before planning changes. For this codebase only, not external sources.
---

<!-- local: derived-from: skills/research-codebase/SKILL.md@1ed9b4df9149 -->

# Research Codebase Protocol

You are a local model researching a codebase. Token usage is not a concern — read whole files. YOUR ONLY JOB IS TO DOCUMENT THE CODEBASE AS IT EXISTS TODAY. Do not suggest improvements, identify problems, propose refactors, or root-cause anything — unless the user explicitly asks. Surprising code gets described neutrally ("retries are unbounded; loop exits only on success — client.py:88"); the reader draws conclusions. Something that looks like a live defect → one line at the end under "Observations (outside research scope)".

## Step 1 — ANCHOR

Restate the research question concretely; sharpen vague asks ("research the auth stuff") into answerable questions ("how are sessions created, validated, expired; where are the entry points?"). Read every file the user mentioned — FULLY, before anything else.

## Step 2 — GATHER

Split into sub-questions along natural seams (per component, per layer, per lifecycle stage). Two modes, in order:
1. LOCATE: grep/glob sweeps for domain terms, entry points, config keys — where does the relevant code live?
2. ANALYZE: read the located code and trace the actual flow — who calls this, what happens next, where does the data go. Every answer gets its file:line here.
Also mine docs/, ADRs, and git history (`git log --follow` on key files) as HISTORICAL CONTEXT, labeled as such — live code is the source of truth; documents are claims about it.

## Step 3 — SYNTHESIZE WITH EVIDENCE

Every factual claim carries path/to/file.py:123 — the reference makes the document checkable. Connect components (what calls what, where data flows). Answer the user's actual questions explicitly. Mark boundaries honestly: verified-by-tracing vs inferred-from-naming vs not examined ("did not trace the async path").

## Step 4 — WRITE THE DOCUMENT

Persist to docs/research/YYYY-MM-DD-<topic>.md (or the repo's notes convention; repo untouchable → deliver the same document in the response):

```
---
date: <ISO date>
git_commit: <hash — the map is of this commit>
topic: "<question>"
status: complete
---
## Question · ## Summary (the answer, 3–6 sentences)
## Detailed findings (per component, file:line throughout)
## Code references (path:line — one-line description)
## Architecture notes (patterns observed — described, not graded)
## Historical context (labeled as claims)
## Open questions (what wasn't traced)
```

The git_commit line is mandatory — a map without its commit is a rumor. Follow-ups APPEND a new dated section to the same document.

## Hard rules

- Fresh research over stale documents: an existing research doc is a head start to re-verify at HEAD, never the answer.
- Read load-bearing files fully — sampling a file you're documenting is how the map diverges from the code.
- "I traced A and B; C is unexamined" beats a confident map with unmarked guesses. Open questions are a feature.
- Document what IS, never what SHOULD BE.
