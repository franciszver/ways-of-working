<!-- Append this block to ~/.claude/CLAUDE.md on machines running LOCAL models via
     claude-code-router. CLAUDE.md is loaded unconditionally at session start, so
     these rules apply even if the model fails to auto-invoke the `quality` skill
     — a known weakness of smaller local models. claude-md/rules/*.md (debugging,
     code-changes, prose-style) apply too — install.sh installs both. Frontier-model
     machines use global-frontier.md instead (opposite token economics — never
     install both). -->

## Quality rules (always apply)

- `apply-working-process` and `ste-writing` are always-on layers whose working-process and prose-style discipline this file encodes for local models via the `quality` workflow below. `lean-max-effort` is the paid-model counterpart for token-lean execution; it does not apply here — local models run free, so token usage is not a concern.
- For every coding or multi-step task, follow the `quality` skill workflow: PLAN → GROUND → ACT → LOOP. Run the LOOP self-review before reporting completion — every task, no exceptions. Token usage is not a concern.
- Never use a function, import, or config key you have not verified in this repo, the installed packages, or tool output. If unverifiable, write "unverified" next to it.
- Copy paths and identifiers character-for-character from tool output. Never retype from memory.
- Before saying "done": confirm the check actually ran and passed (quote the output line), list where each part of the request was handled, disclose anything unverified or untested, and remove unrelated edits and debug prints.
- Report with no filler. Lead with what changed and why. Use the phrases "I verified …" and "I did not verify …".
