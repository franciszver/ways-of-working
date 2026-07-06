<!-- Append this block to ~/.claude/CLAUDE.md on machines running LOCAL models via
     claude-code-router. CLAUDE.md is loaded unconditionally at session start, so these
     rules apply even if the model fails to auto-invoke the `quality` skill — a known
     weakness of smaller local models. Keep this block short; it is read on every
     session. Frontier-model machines use global-frontier.md instead (opposite token
     economics — never install both). -->

## Quality rules (always apply)

- For every coding or multi-step task, follow the `quality` skill workflow: PLAN → GROUND → ACT → LOOP. Run the LOOP self-review before reporting completion — every task, no exceptions. Token usage is not a concern.
- Read a file before editing it. Re-read it after any failed edit. Never edit from memory.
- Never use a function, import, or config key you have not verified in this repo, the installed packages, or tool output. If unverifiable, write "unverified" next to it.
- Copy paths and identifiers character-for-character from tool output. Never retype from memory.
- Never write `...`, `// rest unchanged`, or TODO stubs into a real file. Complete code only.
- After each substantive edit, run the cheapest real check: targeted test → build/typecheck → lint → execute.
- The same command failing the same way twice means your hypothesis is wrong: stop, re-read the full error, re-plan. Never retry the same fix a third time.
- Before saying "done": confirm the check actually ran and passed (quote the output line), list where each part of the request was handled, disclose anything unverified or untested, and remove unrelated edits and debug prints.
- Report with no filler. Lead with what changed and why. Use the phrases "I verified …" and "I did not verify …".
- If truly stuck after two failed approaches, or ending a session mid-task: write `HANDOFF.md` (goal, numbered requirements with status, exact next step, decisions, gotchas, verbatim commands) and say you are stopping. A truthful "stuck" is a good outcome; a guess presented as done is not.
- If `HANDOFF.md` exists when you start, read it first and verify its two cheapest claims before building on it.
