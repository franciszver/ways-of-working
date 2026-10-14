---
name: plain-language
description: Checks prose for AI-writing tells and for clear technical English, then
  strikes what matches. Use whenever prose will be read by a person, especially anything
  shipped publicly (docs, README, UI copy, PR and issue text, emails, applications).
  Complements `write` (process) and `ste-writing` (style); this one is detection and
  removal.
---

# Plain language

`write` decides what to say. `ste-writing` decides how plainly to say it. This skill does a
third job: it checks whether the result reads as machine-generated, and strikes what does.

The check is not taste. It is a set of published, dated observations about what current
models actually produce, held in `references/`.

Use the cached snapshots as they are. Do not check their age. Do not fetch newer versions
unless the user asks. A date in a reference is provenance, not a schedule. A word list is a
set of clues, not an exhaustive test.

## Sources, in priority order

1. **`references/wp-aisigns.md`** is the authority. A local cache of Wikipedia's
   `Wikipedia:Signs of AI writing`, which is community-maintained and revised
   continuously. It carries its own revision id and check date.
2. **`references/ai-tells.md`** corroborates and extends it from six named sources,
   including one peer-reviewed corpus study (Matsui, *Perspectives on Medical Education*,
   2025) covering 135 terms across PubMed 2000 to 2024. Cite that one when a claim has to
   hold up.

Where the two disagree, prefer the Wikipedia cache and note the disagreement.

## The half-life rule

**Constructions outlive vocabulary.** "It's not X, it's Y" has been named as a tell every
year since 2023 and survived three years of prompt engineering against it. Word lists rot
fast: the 2023 register was Latinate and ornate (*delve, tapestry, pivotal*), the 2026
register is plain and monosyllabic (*quietly, shift, matters, lands*). Checking only for
*delve* now misses most current output.

So: check constructions first, vocabulary second, and treat every word list as a clue, not
a full test.

## Check order for a draft

1. AI-vocabulary density, and avoidance of plain copulas (*is*, *has*).
2. Negative parallelism and decorative rule-of-three.
3. Em dashes (U+2014). Remove each one.
4. Formatting: boldface stems, title case, emoji in headings.
5. Promotional puffery and "-ing" clauses that analyse nothing.
6. Does it read like the *signs of human writing* list: plain verbs, hedges, the occasional
   wordy construction a machine would have tidied away.

## Constructions and vocabulary to strike

Do not keep a local copy — grep the draft directly against `references/wp-aisigns.md`
("Negative parallelisms", "Rule of three", `### High density of "AI vocabulary" words`
sections) and `references/ai-tells.md` ("Sentence constructions to strike", "Words and
phrases to strike"). A local copy drifts from the source within weeks; the check order
above tells you when to run it.

## Formatting tells

- Bold-stemmed bullets: every item opening with a **bolded label:** then text.
- Emoji in headings.
- Uniform bullet lengths forming a visual rectangle.
- Rhetorical colons: two-word fragment, colon, payoff.
- Title Case In Headings where the house style is sentence case.

## Em dashes

Strike every em dash. Replace it with a comma, a colon, parentheses, or a new sentence.

The sources do not agree that the em dash proves AI use. Human writers use it too. This
skill removes it anyway, because it is a common mark of machine prose.

Do not swap it for a spaced hyphen or an en dash. Reword the sentence instead.

## AI detectors

Detectors are unreliable in both directions. No check in this skill depends on one. If a
detector and the read-aloud test disagree, the read-aloud test wins.

## Relationship to `ste-writing`

They pull against each other in one place and it needs saying out loud.

`ste-writing` asks for short active sentences. This skill flags runs of three or four
clipped sentences as the current generation's signature. Both are right. The resolution:

> Keep sentences short, but vary their length. One long sentence among short ones is human.
> Four short ones in a row is a fingerprint.

Length variation is the thing to preserve. Neither skill asks for uniformity.

## The test

Read it aloud. If you would not say it to someone standing in front of you, rewrite it.
