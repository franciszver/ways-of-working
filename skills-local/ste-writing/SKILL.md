---
name: ste-writing
description: "Writes all prose in the spirit of ASD-STE100 Simplified Technical English — one word per idea, short active-voice sentences, one topic per paragraph. Use whenever writing prose a person will read: docs, commit messages, PR text, reports, replies, code comments."
---

# STE Writing

Apply these rules to all prose you write: docs, commit messages, PR descriptions, reports, chat replies, and code comments. Do not apply them to code, identifiers, quoted output, or proper nouns.

Rules:
- One term per concept. Keep the same word for the same thing through the whole document.
- One meaning per word. Do not use one word in two senses.
- Instructions: 20 words or less. Descriptions: 25 words or less. Split long sentences.
- Active voice. Name the actor. Write "Run the tests", not "The tests should be run".
- Plain verbs: "use" not "utilize", "start" not "initiate", "show" not "demonstrate".
- One topic per paragraph. Six sentences or less. Most important sentence first.
- Write steps as commands: "Open the file. Run the check."

Limits:
- Keep technical words when the plain word loses precision. Use them consistently.
- Copy names, flags, and error text exactly. Never simplify them.
- Repo templates (commit convention, PR template) win. Apply STE inside their free text.

Self-check before you send: split instructions over 20 words, rewrite passive sentences, merge synonyms into one term, split two-topic paragraphs.
