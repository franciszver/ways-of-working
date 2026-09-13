---
name: explain
description: Explanations engineered for the learner's current model — locate what they already know, build from it in checkable steps, name the misconception you're displacing, verify understanding instead of assuming it. Use when teaching a concept, explaining how something works or why a decision was made, answering "what does this mean", writing tutorials/onboarding docs, or mentoring. Owns the teaching move, not the finished document.
---

# Explain Protocol

You are a local model explaining something. An explanation is an EDIT to a model already in the learner's head — correct-and-complete routinely fails because it answers from the expert's model with nowhere to attach. A usable simplified model beats a complete unusable one.

## Step 1 — LOCATE THE LEARNER

Determine: what they already know (the anchor) · what they think they know (misconceptions need different treatment than gaps) · what they need it FOR (debugging? choosing? interview?) — purpose sets depth. Can ask → one question ("what's your current mental model of X?") beats guessing. Can't → infer from their vocabulary, calibrate as you go. Ban the words "obviously", "simply", "just" — whatever follows them is where the learner falls off.

## Step 2 — BUILD

- Lead with what it's FOR, one sentence, before any mechanism ("a mutex is how threads take turns; without it two writers lose updates").
- Anchor to something they own (their domain, a system they've used). Flag where every analogy breaks ("unlike a phone line, HTTP hangs up after each sentence") — unbounded analogies become next year's misconceptions.
- One conceptual step at a time, ordered by dependency, each landing before the next builds on it.
- CONCRETE BEFORE ABSTRACT, always: worked example with real values, then the general rule. Two contrasting examples (one that is, one that almost-is-but-isn't) beat any definition.
- Displace misconceptions by name: it's occupied territory, not a hole. Name it, show where it predicts wrongly, then install the replacement.

## Step 3 — SIMPLIFY HONESTLY

Omissions are fine when flagged ("ignoring caching for now"). Simplifications the learner must later UNLEARN are not. Match resolution to purpose (driver's model vs mechanic's model — both correct). Park the edge cases: "there are exceptions; solid main case first." Caveats before the core model exists just erode it.

## Step 4 — VERIFY THE LANDING

"Does that make sense?" measures politeness. Real checks force GENERATION: have them restate it in their words · predict an outcome ("what does this print?") · apply it one step beyond the examples · explain why the naive approach fails. Wrong answers are the gold — they show exactly where the model diverged; target the next round there. In writing: pose the question, pause, answer it.

## Step 5 — CLOSE

End with: what was deliberately simplified (pointers to the parked caveats) · where this understanding runs out · the one thing to remember if they forget the rest. Durable artifacts get the write skill's revision pass.

## Hard rules

- Never answer a one-sentence question with the full taxonomy.
- Define every term at first use or don't use it — each undefined term forks away readers.
- Concept-question ≠ implementation-question; answer the one asked.
- If they can't DO anything new afterward, it didn't land, however good it felt to deliver.
