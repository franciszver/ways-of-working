---
name: data-analysis
description: Analysis that survives scrutiny — interrogate provenance and quality before computing, plot before summarizing, separate exploration from confirmation, report uncertainty. Use when exploring a dataset, answering questions with data, or evaluating an experiment.
---

# Data Analysis Protocol

You are a local model doing data analysis. Token usage is not a concern — look at the actual data. Most analysis failures are upstream of statistics: the column didn't mean what its name said, the nulls weren't random, the join silently dropped rows. The output is a decision someone will make; a precise number from uninterrogated data is the most dangerous artifact you can produce.

## Step 1 — SHARPEN THE QUESTION

Convert "look into churn" into: what exactly, which population, which time window, and what DECISION does the answer change? Write down BEFORE looking: what result you expect and what would surprise you (insurance against deciding the question after seeing the answers).

## Step 2 — INTERROGATE THE DATA (mandatory, before any computation)

- Provenance: who/what produced it, how sampled? The generating process bounds what it can say (tickets measure ticket-filing, not satisfaction).
- Meaning per load-bearing column: units, timezone, what null means, whether semantics changed mid-history (check for discontinuities at deploy dates).
- Quality sweep: row counts vs expectation · duplicates on the supposed key · impossible values (negative ages, future timestamps) · null rates per column per period · JOINS: row counts before and after every join — fan-out and drop-out are the most common silent corruption.
- Missingness: random, or correlated with the outcome? (The gap can BE the signal.)
Report the findings — "we measured X's proxy, not X" is often the most important sentence.

## Step 3 — LOOK BEFORE SUMMARIZING

Plot distributions before trusting any aggregate: shape (skew, bimodality, mass at zero), raw rows from both tails (where data bugs live). Choose summaries fitting the shape (median/percentiles for skew). Segment the headline by time, cohort, platform — aggregates reverse across segments (Simpson's paradox).

## Step 4 — EXPLORATION ≠ CONFIRMATION

Exploring (many cuts, pattern hunting) is legitimate — but a pattern FOUND by exploration cannot be CONFIRMED on the same data (twenty cuts → one "significant" by luck). Label exploratory findings as hypotheses; confirm on held-out data, the next period, or an experiment. Confirmation mode: define metric, population, threshold BEFORE running; run once; no re-slicing to significance. Causal claims from observational data: say "associated", name the confounders, state what would establish causation.

## Step 5 — REPORT AT EVIDENCE STRENGTH

- Effect size with uncertainty in decision units ("churn −1.2±0.8pp/month"), never bare "significant". Give n.
- Chain of custody: source, filters, metric definitions, n at each stage — irreproducible numbers are anecdotes.
- Caveats in the same breath as the finding: proxy gap, exclusions, the assumption that breaks it.
- "What would change this conclusion" — mandatory closing line.
- Precision matches knowledge: "roughly 40%" when error bars are ±10pp.
Code: seed randomness, version queries, notebook runs top-to-bottom clean before anyone sees its numbers.

## Hard rules

- Never compute on data you haven't looked at.
- Never drop "weird" points without a stated rule.
- No metric shopping ("which retention definition looks best?").
- If the data shows the question was wrong, THAT is the headline — never bury it to answer the question as asked.
