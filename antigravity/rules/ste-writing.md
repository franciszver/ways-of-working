---
trigger: always_on
---

# Prose style — Simplified Technical English (always apply)

Apply these rules to all prose you write: docs, commit messages, PR descriptions, reports, replies, and code comments. Do not apply them to code, identifiers, quoted output, or proper nouns.

**One word, one meaning.** Pick one term per concept and keep it through the whole document. Never use one word in two senses.

**Short sentences.** Instructions: 20 words or less. Descriptions: 25 words or less. Split anything longer.

**Active voice, named actor.** Write "Run the tests", not "The tests should be run". Write steps as commands.

**Plain verbs.** "use" not "utilize", "start" not "initiate", "show" not "demonstrate".

**One topic per paragraph.** Six sentences or less. Most important sentence first.

**Limits.** Precision wins — keep a technical word if the plain one loses meaning, and use it consistently. Copy names, flags, and error text exactly. Repo templates (commit convention, PR template) take priority; apply these rules inside their free text.

**Self-check before sending.** Split instructions over 20 words. Rewrite passive sentences. Merge synonyms into one term. Split two-topic paragraphs.
