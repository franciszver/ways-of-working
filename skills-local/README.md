# skills-local — compact skills for local models

Drop-in skills that make a local model (Qwen, GPT-OSS, etc.) running inside Claude Code via claude-code-router produce frontier-style output: plan before acting, verify instead of guessing, and self-review in a loop before ever saying "done".

A skill cannot add raw capability to the weights — what it can do is eliminate the process failures that account for most of the perceived quality gap: invented APIs, edits made from memory, unverified "success", and stopping one iteration too early. That is what these files target.

These are the **local-model variants**: shorter, more imperative, and explicitly told that token usage is not a concern (local tokens are free — thoroughness wins). The judgment-dense canonical versions for Opus/Sonnet live in [`../skills/`](../skills/). Install one profile per setup, not both — the packs share names by design so either can answer to the same muscle memory.

## What's in the box

```
quality/SKILL.md        Always-on workflow: PLAN → GROUND → ACT → LOOP. Auto-invoked
                        on coding/agentic tasks, also callable as /quality. Ends every
                        task with a mandatory self-review loop (up to 3 rounds).
iterate/SKILL.md        /iterate [rounds] [focus] — manual extra critique-and-revise
                        rounds when you want to push harder on something specific.
                        User-invoked only (disable-model-invocation), so the model
                        can never recurse into it on its own.
```

The compact always-on rules for CLAUDE.md live at [`../claude-md/global-local.md`](../claude-md/global-local.md) — install them too (see "Why the snippet" below).

## Install

```bash
mkdir -p ~/.claude/skills
cp -r quality iterate ~/.claude/skills/

# strongly recommended:
cat ../claude-md/global-local.md >> ~/.claude/CLAUDE.md
```

If `~/.claude/skills/` did not exist before this session, restart Claude Code once so the directory gets watched. After that, edits to the SKILL.md files take effect live — no restart needed.

Project-scoped alternative: put the same folders in `<repo>/.claude/skills/` to version them with a repo.

## Why the snippet

Skills are invoked when the model decides they're relevant, and smaller local models under-trigger skills — sometimes they just don't call them. CLAUDE.md is loaded unconditionally at session start, so the snippet guarantees the core rules apply even on tasks where the skill never fires, and it explicitly tells the model to follow the `quality` workflow. Skill + snippet is belt and suspenders; the snippet alone is the belt.

## Verify it's working

1. Type `/` in Claude Code — `quality` and `iterate` should appear in the command list.
2. Give it a small real task ("add input validation to X and make sure it still passes tests"). The response should visibly show the phases: a short plan with a Definition of Done, reads before edits, a check run after edits, and a final review round with PASS/FAIL criteria and quoted command output.
3. If the structure doesn't appear, the model skipped the skill — confirm the CLAUDE.md snippet is installed, or invoke `/quality <task>` explicitly.

## Usage patterns

- Normal work: just prompt as usual. The workflow and end-of-task loop run automatically.
- Not good enough yet: `/iterate` (2 more rounds), `/iterate 4` (four rounds), `/iterate 3 error handling and edge cases` (focused attack).
- Brand-new task with maximum rigor: `/iterate 3 <task description>` — it will execute the task under the workflow, then loop it.

## Tuning the text for your model

These files are prompts, so iterate on them like prompts. The knobs that matter most:

- Model over-plans trivial edits → tighten the "trivial task" line in Phase 1, or delete steps 2–3 of PLAN.
- Reviews feel shallow / always "0 defects" → in the Attack step, add "you must attempt at least N candidate findings before declaring the work clean" or add defect categories specific to your stack.
- Model claims success without running checks → the strongest lever is the "quote the decisive output line verbatim" requirement; make it louder, and consider requiring the full command + exit code.
- Loop runs too long on big refactors → lower the round cap in Phase 4 from 3 to 2.
- Rules ignored late in long sessions → local models degrade on instruction-following as context grows; the fix is shorter sessions per task, not longer rules.

## Quick A/B

Pick one real bug or small feature. Run it in a scratch branch with the skills removed, then again with them installed (same prompt). Diff the two results against the acceptance criteria the LOOP phase generates. That comparison, on your model and your codebase, is worth more than any benchmark.
