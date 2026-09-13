---
paths:
  - "**/*.{py,ts,js,go,rs,sh}"
---

## Code changes

Read a file before editing it; re-read it after any failed edit — never edit from memory. Complete code only — never `...`, stubs, or "rest unchanged" placeholders in real files. Match surrounding style. No drive-by fixes: log them, stay in scope, report them at the end. After substantive edits, run the cheapest real check (targeted test → typecheck → lint → run).

**Token discipline.** Read surgically (ranges, grep) — never re-read a file that hasn't changed. Don't echo file contents or tool output back. No narration ("Now I will…"), no journey recaps. Edit in place; never regenerate a file to change three lines. Batch related edits, then verify the batch.
